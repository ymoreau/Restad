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
  class DocumentExploder
    attr_reader :root_tag_name, :docname_attribute_name, :docname_tag_name
    attr_accessor :refresh_frequency, :max_mem
#-------------------------------------------------------------------------------
    def initialize root_tag_name, docname_attribute_name, docname_tag_name
      @root_tag_name = root_tag_name
      @docname_attribute_name = docname_attribute_name
      @docname_tag_name = docname_tag_name
    end
  end
#===============================================================================
  class Parser
    DOC_NAME_MAX_LENGTH = 255
    TAG_NAME_MAX_LENGTH = 255
    ATTRIBUTE_NAME_MAX_LENGTH = 255

    attr_reader :error_log

#-------------------------------------------------------------------------------
    def initialize db, use_temporary_files, use_unique_doc_names, is_verbose, temp_dir, document_exploder
      @error_log = ""
      @data_manager = DataManager.new(db, use_temporary_files, temp_dir)
      @data_manager.set_unique_doc_names(is_verbose) if use_unique_doc_names
      @data_manager.init_parsing(is_verbose)
      @multiple_documents = (not document_exploder.nil?)
      @listener = Listener.new(self, @data_manager, document_exploder, @error_log)
    end
#-------------------------------------------------------------------------------
    def parse filename
      begin
        docname = filename
        docname.cut!(Parser::DOC_NAME_MAX_LENGTH)
        @data_manager.start_document(docname) unless @multiple_documents

        @listener.start_new_file
        @listener.clear

        case File.extname(filename)
        when ".xml", ".XML"
          io = File.new(filename)
        when ".odt", ".ODT"
          io = ZipReader.open_odt(filename)
        else
          raise RestadException, "Wrong file format '#{File.extname(filename)}'"
        end
        parser = Parsers::StreamParser.new(io, @listener)
        parser.parse

        unless @multiple_documents
          text = @listener.raw_text
          @data_manager.end_document(text)
        end

      rescue => e
        @error_log << "Indexing '#{filename}' failed: #{e}\n"
        return false
      end
      return true
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
    def initialize parser, data_manager, document_exploder, log_string
      @parser = parser
      @data_manager = data_manager
      @document_exploder = document_exploder
      @docs_count = 0
      @stack = Array.new
      @tag_names_count = Hash.new { |hash,key| hash[key] = Hash.new(1) } # MAP[tag_name][parent_id] => count
      @raw_text = String.new
      @depth = 0
      @error_log = log_string
      # If doc exploder is nil, we parse the whole file
      @is_parsing_doc = @document_exploder.nil?
    end
#-------------------------------------------------------------------------------
    def start_new_file
      @docs_count = 0
    end
#-------------------------------------------------------------------------------
    def clear
      @stack.clear
      @tag_names_count.clear
      @raw_text.clear
      @depth = 0
      @waiting_for_docname = false
    end
#-------------------------------------------------------------------------------
    def tag_start name, attributes
      @depth += 1
      name.clean!
      name.cut!(Parser::TAG_NAME_MAX_LENGTH)
     
      # Check for a starting document
      unless @is_parsing_doc
        if name == @document_exploder.root_tag_name
          @is_parsing_doc = true
          @starting_depth = @depth
          @data_manager.start_document
          @docs_count += 1
          unless @document_exploder.docname_attribute_name.nil?
            docname = attributes[@document_exploder.docname_attribute_name]
            raise RestadException, "Document has no attribute '#{@document_exploder.docname_attribute_name}'" if docname.nil?
            if docname.size > Parser::DOC_NAME_MAX_LENGTH
              docname.slice!(Parser::DOC_NAME_MAX_LENGTH, docname.size - 1)
              @error_log << "Document name is too long (>#{Parser::DOC_NAME_MAX_LENGTH}) :\n\t'#{docname}'\n"
            end
            @data_manager.set_doc_name(docname)
          end
        else
          return # ignore out-of-document tags
        end
      end

      if (not @document_exploder.nil?) and @is_parsing_doc and (not @document_exploder.docname_tag_name.nil?)
        @waiting_for_docname = name == @document_exploder.docname_tag_name and (not @data_manager.doc_name.empty?)
      end

      current_tag = Tag.new(name)

      current_tag.id_tag_name = @data_manager.tag_name_id(name)
      current_tag.parent_tag = @stack.last.id_tag unless @stack.empty?
      current_tag.id_tag = @data_manager.tag_id

      current_tag.tag_num = @tag_names_count[name][current_tag.parent_tag]
      @tag_names_count[name][current_tag.parent_tag] += 1

      add_attributes(current_tag.id_tag, attributes) unless attributes.empty?
      @stack.push current_tag
    end
#-------------------------------------------------------------------------------
    def add_attributes tag_id, attributes
      att_names = Array.new
      attributes.each do |frozen_att_name, att_value|
        next if frozen_att_name.empty?

        att_name = frozen_att_name.dup
        att_name.strict_clean!
        att_name.cut!(Parser::ATTRIBUTE_NAME_MAX_LENGTH)

        # Check if the attribute name was not already set for this tag
        if att_names.include?(att_name)
          @error_log << "Tag have two attributes with the same name (tag_id: #{tag_id}, attribute: #{att_name})\n"
          next
        end
        att_names.push(att_name)

        att_name_id = @data_manager.attribute_name_id(att_name)
        att_value.clean!
        @data_manager.add_attribute(tag_id, att_name_id, att_value)
      end
    end
#-------------------------------------------------------------------------------
    def tag_end name
      return unless @is_parsing_doc

      # Check for the end of the document (if multiple documents)
      if @is_parsing_doc and (not @document_exploder.nil?)
        if name == @document_exploder.root_tag_name
          if @starting_depth < @depth
            @error_log << "Document contains a document-root-tag '#{@document_exploder.root_tag_name}'\n"
          elsif @starting_depth > @depth
            raise RestadException, "Expecting a matching document-root-tag (i.e. matching the begining one)"
          else # @starting_depth == @depth -> matching end-tag
            tag = @stack.last
            tag.start_offset = @last_offset if tag.start_offset.nil?
            tag.end_offset = @last_offset
            @data_manager.add_tag(tag)
            @data_manager.end_document(@raw_text)

# TODO
# refresh
# message
            if @docs_count > @document_exploder.refresh_frequency
              used_mem = Restad::Utils.used_memory
              @parser.flush_buffers if used_mem > (0.8 * @document_exploder.max_mem).to_i
              @docs_count = 0
            end

            clear
            @is_parsing_doc = false
            return
          end
        end
      end

      tag = @stack.last
      tag.start_offset = @last_offset if tag.start_offset.nil?
      tag.end_offset = @last_offset
      @data_manager.add_tag(tag)

      @depth -= 1
      @stack.pop
    end
#-------------------------------------------------------------------------------
    def text text
      return unless @is_parsing_doc

      text.clean!

      if @waiting_for_docname
        docname = text
        if docname.size > Parser::DOC_NAME_MAX_LENGTH
          docname.slice!(Parser::DOC_NAME_MAX_LENGTH, docname.size - 1)
          @error_log << "Document name is too long (>#{Parser::DOC_NAME_MAX_LENGTH}) :\n\t'#{docname}'\n"
        end
        @data_manager.set_doc_name(docname)
        @waiting_for_docname = false;
      end

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

