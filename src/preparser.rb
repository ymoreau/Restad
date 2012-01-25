#!/usr/bin/env ruby
# XML preparser

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

require './utils'
require './parser'
require 'pg'

require 'rexml/document'
require 'rexml/streamlistener'
include REXML

module Restad
#===============================================================================
  class Preparser
    attr_reader :error_log, :tag_names, :attribute_names, :existing_tag_names, :existing_attribute_names
    attr_accessor :tmp_tag_names, :tmp_attribute_names

#-------------------------------------------------------------------------------
    def initialize db
      @db = db
      @error_log = ""
      @tag_names = Hash.new
      @attribute_names = Hash.new

      @existing_tag_names = Hash.new
      @existing_attribute_names = Hash.new
      res = @db.exec("SELECT tag_name FROM tag_names")
      res.each {|row| @existing_tag_names[row['tag_name']] = nil }
      res = @db.exec("SELECT attribute_name FROM attribute_names")
      res.each {|row| @existing_attribute_names[row['attribute_name']] = nil }
    end

#-------------------------------------------------------------------------------
    def commit
      unless @tag_names.empty?
        tag_query = "INSERT INTO tag_names(tag_name) VALUES "
        sep = ""
        @tag_names.each_key do |name| 
          tag_query << "#{sep}('#{PGconn.escape_string(name)}')"
          sep = ", "
        end
        @db.exec(tag_query)
      end
      unless @attribute_names.empty?
        att_query = "INSERT INTO attribute_names(attribute_name) VALUES "
        sep = ""
        @attribute_names.each_key do |name| 
          att_query << "#{sep}('#{PGconn.escape_string(name)}')"
          sep = ", "
        end
        @db.exec(att_query)
      end
    end

#-------------------------------------------------------------------------------
    def parse filename
      @tmp_tag_names = Hash.new
      @tmp_attribute_names = Hash.new

      ret = false
      if File.extname(filename) == ".dtd"
        ret = parse_dtd(filename)
      else
        ret = parse_xml(filename)
      end

      flush if ret

      return ret
    end

#-------------------------------------------------------------------------------
    def flush
      @tmp_tag_names.each_key { |key| @tag_names[key] = nil }
      @tmp_attribute_names.each_key { |key| @attribute_names[key] = nil }
    end

#-------------------------------------------------------------------------------
    def parse_dtd filename
      content = File.read(filename)
      content.scan(/\<!ELEMENT (\w*) .*\>/) do |capture|
        tagname = capture[0].downcase
        tagname.slice!(Parser::TAG_NAME_MAX_LENGTH, tagname.size - 1) if tagname.size > Parser::TAG_NAME_MAX_LENGTH
        @tmp_tag_names[tagname] = nil unless @tag_names.has_key?(tagname) or @existing_tag_names.has_key?(tagname)
      end
      content.scan(/\<!ATTLIST \w* (\w*) .*\>/) do |capture|
        attname = capture[0].downcase
        attname.slice!(Parser::ATTRIBUTE_NAME_MAX_LENGTH, attname.size - 1) if attname.size > Parser::ATTRIBUTE_NAME_MAX_LENGTH
        @tmp_attribute_names[attname] = nil unless @attribute_names.has_key?(attname) or @existing_attribute_names.has_key?(attname)
      end
      return true
    end

#-------------------------------------------------------------------------------
    def parse_xml filename
      begin
        listener = PreparserListener.new(self)
        parser = Parsers::StreamParser.new(File.new(filename), listener)
        parser.parse
      rescue RestadException, ParseException => e
        @error_log << "Preparsing '#{filename}' failed: #{e}\n"
        return false
      end
      return true
    end
  end

#===============================================================================
  class PreparserListener
    include StreamListener

#-------------------------------------------------------------------------------
    def initialize preparser
      @preparser = preparser
    end

#-------------------------------------------------------------------------------
    def tag_start name, attributes
      tagname = name.downcase
      tagname.slice!(Parser::TAG_NAME_MAX_LENGTH, tagname.size - 1) if tagname.size > Parser::TAG_NAME_MAX_LENGTH
      @preparser.tmp_tag_names[tagname] = nil unless @preparser.tag_names.has_key?(tagname) or @preparser.existing_tag_names.has_key?(tagname)
      
      attributes.each do |frozen_att_name, att_value|
        next if frozen_att_name.empty?

        attname = frozen_att_name.downcase
        attname.slice!(Parser::ATTRIBUTE_NAME_MAX_LENGTH, attname.size - 1) if attname.size > Parser::ATTRIBUTE_NAME_MAX_LENGTH
        @preparser.tmp_attribute_names[attname] = nil unless @preparser.attribute_names.has_key?(attname) or @preparser.existing_attribute_names.has_key?(attname)
      end
    end

#-------------------------------------------------------------------------------
    def tag_end name
    end

#-------------------------------------------------------------------------------
    def text text
    end

  end
end
