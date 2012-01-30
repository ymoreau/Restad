#!/usr/bin/env ruby
# Temporary/Database data interface

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
require 'pg'
require 'stringio'

module Restad
#===============================================================================
  class FilesOpened < RestadException
  end

#===============================================================================
  class DataManager

    attr_reader :doc_name

    @@file_names = {:docs => "tmp_docs.dat", :tags => "tmp_tags.dat", \
      :tag_attributes => "tmp_tag_attributes.dat"}

#-------------------------------------------------------------------------------
    def initialize db, use_files, temp_dir
      @db = db
      @use_files = use_files
      @temp_dir = temp_dir
      @data_io = Hash.new
      @doc_buffers = Hash.new
# TODO fix for prototype 2 if used in parallel
      @unique_doc_names = false
    end
#-------------------------------------------------------------------------------
    def open_buffers mode = "r"
      errors = ""
      @@file_names.each do |key,value|
        if @data_io.has_key?(key)
          errors << "#{key} file already opened"
          next
        end

        if @use_files
          raise RestadException, "Temporary directory is nil" if @temp_dir.nil?
          @data_io[key] = File.new("#{@temp_dir}#{value}", mode)
        else
          @data_io[key] = StringIO.new
        end
      end

      raise FilesOpened, errors unless errors.empty?
    end
#-------------------------------------------------------------------------------
    def close_buffers
      @data_io.each_value {|file| file.close} if @use_files
      load_string_buffers unless @use_files
      @data_io.clear
    end
#-------------------------------------------------------------------------------
    def flush_buffers
      @data_io.each_value {|file| file.flush} if @use_files
      load_string_buffers unless @use_files
    end
#-------------------------------------------------------------------------------
    def init_parsing is_verbose = false
      open_buffers("w")
      # Initialize the doc-buffers
      @@file_names.each_key {|key| @doc_buffers[key] = String.new}

      # Read the existing unique strings
      @known_tag_names = Hash.new
      cache_tag_names
      @known_attribute_names = Hash.new
      cache_attribute_names

      puts "#{@known_tag_names.size} tag names read in database" if is_verbose
      puts "#{@known_attribute_names.size} attribute names read in database" if is_verbose
    end
#-------------------------------------------------------------------------------
    def cache_tag_names
      res = @db.exec("SELECT * FROM tag_names")
      res.each {|row| @known_tag_names[row['tag_name']] = row['id_tag_name'].to_i }
    end
#-------------------------------------------------------------------------------
    def add_tag_name name
      begin
        res = @db.exec("INSERT INTO tag_names(tag_name) VALUES('#{PGconn.escape_string(name)}');")
      rescue PGError => e # Ignore any unique tag error
      raise e
      end
      cache_tag_names
    end
#-------------------------------------------------------------------------------
    def cache_attribute_names
      res = @db.exec("SELECT * FROM attribute_names")
      res.each {|row| @known_attribute_names[row['attribute_name']] = row['id_attribute_name'].to_i }
    end
#-------------------------------------------------------------------------------
    def add_attribute_name name
      begin
        res = @db.exec("INSERT INTO attribute_names(attribute_name) VALUES('#{PGconn.escape_string(name)}');")
      rescue PGError # Ignore any unique tag error
      end
      cache_attribute_names
    end
#-------------------------------------------------------------------------------
    def load_temporary_files
      open_buffers("r")
      sql_copy_all
      close_buffers
    end
#-------------------------------------------------------------------------------
    def load_string_buffers
      @data_io.each_value {|stringio| stringio.rewind } # Seek 0 for reading
      sql_copy_all
      @data_io.each_key {|key| @data_io[key] = StringIO.new }
    end
#-------------------------------------------------------------------------------
    def sql_copy_all
      @db.transaction do
        DBUtils.sql_copy(@db, "docs(id_doc, doc_name, text)", @data_io[:docs], "docs")
        DBUtils.sql_copy(@db, "tags(id_doc, id_tag, id_tag_name, tag_order_position, parent_id, starting_offset, ending_offset)", @data_io[:tags], "tags")
        DBUtils.sql_copy(@db, "tag_attributes(id_tag, id_doc, id_attribute_name, attribute_value)", @data_io[:tag_attributes], "tag_attributes")
      end
    end
#-------------------------------------------------------------------------------
# TODO fix for prototype 2 if used in parallel
    def set_unique_doc_names is_verbose
      @unique_doc_names = true
      @doc_names = Hash.new

      res = @db.exec("SELECT doc_name FROM docs")
      res.each {|row| @doc_names.store(row['doc_name'], nil)}
      puts "#{@doc_names.size} existing doc names read from database" if is_verbose
    end
#-------------------------------------------------------------------------------
# Documents
#-------------------------------------------------------------------------------
    def start_document doc_name = ""
# TODO fix for prototype 2 if used in parallel
      if @unique_doc_names and (not doc_name.empty?)
        raise RestadException, "Doc '#{doc_name}' already exists in database" if @doc_names.has_key?(doc_name)
        @doc_names.store(doc_name,nil)
      end

      @doc_buffers.each_value {|value| value.clear }
      @tag_count = 0
      @doc_name = doc_name
      @doc_id = DBUtils::next_id(@db, "docs_id_doc_seq")
    end
#-------------------------------------------------------------------------------
    def set_doc_name doc_name
# TODO fix for prototype 2 if used in parallel
      if @unique_doc_names
        raise RestadException, "Doc '#{doc_name}' already exists in database" if @doc_names.has_key?(doc_name)
        @doc_names.store(doc_name,nil)
      end
      @doc_name = doc_name if @doc_name.empty?
    end
#-------------------------------------------------------------------------------
    def end_document text
      @doc_buffers[:docs] << "#{@doc_id}\t'#{PGconn.escape_string(@doc_name)}'\t'#{PGconn.escape_string(text)}'\n"

      @doc_buffers.each {|key, value| @data_io[key] << value }
    end
#-------------------------------------------------------------------------------
# Tags
#-------------------------------------------------------------------------------
    def tag_name_id tag_name
      tries = 0
      until @known_tag_names.has_key?(tag_name)
        raise RestadException, "Can not add new tag name : '#{tag_name}' #{tries} tries." if tries > DBUtils::MAX_TRIES

        add_tag_name(tag_name)
        tries += 1
      end
      return @known_tag_names[tag_name]
    end
#-------------------------------------------------------------------------------
    def tag_id
      @tag_count += 1
    end
#-------------------------------------------------------------------------------
    def add_tag tag
      raise RestadException, "Wrong starting and ending offset : #{tag.start_offset};#{tag.end_offset}" if tag.start_offset > tag.end_offset

      tag.parent_tag = "" if tag.parent_tag.nil?
      @doc_buffers[:tags] << "#{@doc_id}\t#{tag.id_tag}\t#{tag.id_tag_name}\t#{tag.tag_num}\t#{tag.parent_tag}\t#{tag.start_offset}\t#{tag.end_offset}\n"
    end
#-------------------------------------------------------------------------------
# Attributes
#-------------------------------------------------------------------------------
    def attribute_name_id attribute_name
      tries = 0
      until @known_attribute_names.has_key?(attribute_name)
        raise RestadException, "Can not add new attribute name : '#{attribute_name}' #{tries} tries." if tries > DBUtils::MAX_TRIES

        add_attribute_name(attribute_name)
        tries += 1
      end
      return @known_attribute_names[attribute_name]
    end
#-------------------------------------------------------------------------------
    def add_attribute tag_id, attribute_name_id, attribute_value
      @doc_buffers[:tag_attributes] << "#{@doc_id}\t#{tag_id}\t#{attribute_name_id}\t'#{PGconn.escape_string(attribute_value)}'\n"
    end
  end

end
