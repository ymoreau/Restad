#!/usr/bin/env ruby
# XML parser

#--
## This file is a part of the Restad project
## https://github.com/ymoreau/Restad
##
## Copyright (C) 2011 LIA (www.lia.univ-avignon.fr)
##
## This program is free software: you can redistribute it and/or modify
## it under the terms of the GNU General Public License as published by
## the Free Software Foundation, either version 3 of the License, or
## (at your option) any later version.
##
## This program is distributed in the hope that it will be useful,
## but WITHOUT ANY WARRANTY; without even the implied warranty of
## MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
## GNU General Public License for more details.
##
## You should have received a copy of the GNU General Public License
## along with this program.  If not, see <http://www.gnu.org/licenses/>.
##++
#

require './data_manager.rb'

require 'rexml/document'
require 'rexml/streamlistener'
include REXML

module Restad
#===============================================================================
  class Parser
    TAG_NAME_MAX_LENGTH = 255
    ATTRIBUTE_NAME_MAX_LENGTH = 255
    TOKEN_MAX_LENGTH = 255

    attr_reader :error_log

#-------------------------------------------------------------------------------
    def initialize db, use_temporary_files, use_unique_doc_names, is_verbose, temp_dir
      @error_log = ""
      @use_temporary_files = use_temporary_files
      @data_manager = DataManager.new(db, use_temporary_files, temp_dir)
      @data_manager.set_unique_doc_names(is_verbose) if use_unique_doc_names
      @data_manager.init_parsing(is_verbose)
      @listener = Listener.new(@data_manager, @error_log)
    end
#-------------------------------------------------------------------------------
    def parse filename
      begin
        @data_manager.start_document(filename)

        parser = Parsers::StreamParser.new(File.new(filename), @listener)
        parser.parse

        text = @listener.raw_text
        index_text(text)
        @data_manager.end_document(text)

        @listener.clear

      rescue Restad::RestadException, PGError, ParseException => e
        @error_log << "Indexing '#{filename}' failed: #{e}\n"
        return false
      end
      return true
    end
#-------------------------------------------------------------------------------
    def index_text text
      token_positions = Hash.new { |hash, key| hash[key] = Array.new }

      offset = 0
      while true
        position = text.index(/\w{2,}/, offset)
        break if position.nil?
        token = text.match(/(\w{2,})/, offset)[1].to_s
        token.slice!(Parser::TOKEN_MAX_LENGTH, token.size - 1) if token.size > Parser::TOKEN_MAX_LENGTH

        token_positions[@data_manager.token_id(token)].push position
        offset = position + token.length
      end

      token_positions.each {|id_token, positions| @data_manager.add_token_index(id_token, positions) }
    end
#-------------------------------------------------------------------------------
    def flush_buffers
      @data_manager.flush_buffers
    end
#-------------------------------------------------------------------------------
    def close_buffers
      @data_manager.close_buffers
    end
  end

#===============================================================================
  class Tag
    attr_accessor :name, :id_tag_name, :id_tag, :parent_tag, :tag_num, :start_offset, :end_offset

    def initialize name
      @name = name
      @start_offset = nil
    end
  end

#===============================================================================
  class Listener
    include StreamListener

    attr_reader :raw_text

#-------------------------------------------------------------------------------
    def initialize data_manager, log_string
      @data_manager = data_manager
      @stack = Array.new
      @tag_names_count = Hash.new 0 # default value
      @raw_text = String.new
      @error_log = log_string
    end
#-------------------------------------------------------------------------------
    def clear
      @stack.clear
      @tag_names_count.clear
      @raw_text.clear
    end
#-------------------------------------------------------------------------------
    def tag_start name, attributes
      name.downcase!
      name.slice!(Parser::TAG_NAME_MAX_LENGTH, name.size - 1) if name.size > Parser::TAG_NAME_MAX_LENGTH
      current_tag = Tag.new(name)

      current_tag.id_tag_name = @data_manager.tag_name_id(name)
      current_tag.tag_num = @tag_names_count[name]
      @tag_names_count[name] += 1

      current_tag.parent_tag = @stack.last.id_tag unless @stack.empty?

      current_tag.id_tag = @data_manager.tag_id
      add_attributes(current_tag.id_tag, attributes) unless attributes.empty?
      @stack.push current_tag
    end
#-------------------------------------------------------------------------------
    def add_attributes tag_id, attributes
      att_names = Array.new
      attributes.each do |frozen_att_name, att_value|
        next if frozen_att_name.empty?

        att_name = frozen_att_name.downcase
        att_name.slice!(Parser::ATTRIBUTE_NAME_MAX_LENGTH, att_name.size - 1) if att_name.size > Parser::ATTRIBUTE_NAME_MAX_LENGTH

        # Check if the attribute name was not already set for this tag
        if att_names.include?(att_name)
          @error_log << "Tag have two attributes with the same name (tag_id: #{tag_id}, attribute: #{att_name})\n"
          next
        end
        att_names.push(att_name)

        att_name_id = @data_manager.attribute_name_id(att_name)

        att_value.gsub!(/\s+/, " ")
        att_value_id = @data_manager.attribute_value_id(att_value)
        
        @data_manager.add_attribute(tag_id, att_name_id, att_value_id)
      end
    end
#-------------------------------------------------------------------------------
    def tag_end name
      tag = @stack.last
      tag.start_offset = @last_offset if tag.start_offset.nil?
      tag.end_offset = @last_offset
      @data_manager.add_tag(tag)

      @stack.pop
    end
#-------------------------------------------------------------------------------
    def text text
      text.strip!
      text.gsub!(/\s+/, " ")

      # Set the starting offset to all tags since last text
      unless @stack.empty?
        i = -1
        while @stack[i].start_offset.nil? do
          @stack[i].start_offset = @raw_text.size
          i -= 1
          break if @stack[i].nil? # We've reached the begining
        end
      end
      @raw_text << text + " " unless text.empty?
      @last_offset = @raw_text.size
    end
  end

end

