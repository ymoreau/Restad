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

    @@file_names = {:docs => "tmp_docs.dat", :tags => "tmp_tags.dat", \
      :tag_names => "tmp_tag_names.dat", :tag_attributes => "tmp_tag_attributes.dat", \
      :attribute_names => "tmp_attribute_names.dat", :attribute_values => "tmp_attribute_values.dat", \
      :inverted_index => "tmp_inverted_index.dat", :tokens => "tmp_tokens.dat"}

#-------------------------------------------------------------------------------
    def initialize db, use_files, temp_dir
      @db = db
      @use_files = use_files
      @temp_dir = temp_dir
      @data_io = Hash.new
      @doc_buffers = Hash.new
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

      # Read the id counts
      @doc_count = DBUtils.max_id(@db, 'id_doc', 'docs')
      @tag_count = DBUtils.max_id(@db, 'id_tag', 'tags')
      @tag_names_count = DBUtils.max_id(@db, 'id_tag_name', 'tag_names')
      @attribute_names_count = DBUtils.max_id(@db, 'id_attribute_name', 'attribute_names')
      @attribute_values_count = DBUtils.max_id(@db, 'id_attribute_value', 'attribute_values')
      @token_count = DBUtils.max_id(@db, 'id_token', 'tokens')

      # Read the existing unique strings
      @known_tag_names = Hash.new
      @known_attribute_names = Hash.new
      @known_attribute_values = Hash.new
      @known_tokens = Hash.new

      res = @db.exec("SELECT * FROM tag_names")
      res.each {|row| @known_tag_names[row['tag_name']] = row['id_tag_name'].to_i }
      puts "#{@known_tag_names.size} tag names read in database" if is_verbose

      res = @db.exec("SELECT * FROM attribute_names")
      res.each {|row| @known_attribute_names[row['attribute_name']] = row['id_attribute_name'].to_i }
      puts "#{@known_attribute_names.size} attribute names read in database" if is_verbose

      res = @db.exec("SELECT * FROM attribute_values")
      res.each {|row| @known_attribute_values[row['attribute_value']] = row['id_attribute_value'].to_i }
      puts "#{@known_attribute_values.size} attribute values read in database" if is_verbose

      res = @db.exec("SELECT * FROM tokens")
      res.each {|row| @known_tokens[row['token']] = row['id_token'].to_i }
      puts "#{@known_tokens.size} tokens read in database" if is_verbose
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
        DBUtils.sql_copy(@db, "tags(id_tag, id_doc, id_tag_name, tag_num, parent_tag, starting_offset, ending_offset)", @data_io[:tags], "tags")
        DBUtils.sql_copy(@db, "tag_names(id_tag_name, tag_name)", @data_io[:tag_names], "tag_names")
        DBUtils.sql_copy(@db, "tag_attributes(id_tag, id_attribute_name, id_attribute_value)", @data_io[:tag_attributes], "tag_attributes")
        DBUtils.sql_copy(@db, "attribute_names(id_attribute_name, attribute_name)", @data_io[:attribute_names], "attribute_names")
        DBUtils.sql_copy(@db, "attribute_values(id_attribute_value, attribute_value)", @data_io[:attribute_values], "attribute_values")
        DBUtils.sql_copy(@db, "tokens(id_token, token)", @data_io[:tokens], "tokens")
        DBUtils.sql_copy(@db, "inverted_index(id_doc,id_token,positions)", @data_io[:inverted_index], "inverted_index")
      end
    end
#-------------------------------------------------------------------------------
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
    def start_document doc_name
      if @unique_doc_names
        raise RestadException, "Doc '#{doc_name}' already exists in database" if @doc_names.has_key?(doc_name)
        @doc_names.store(doc_name,nil)
      end

      @doc_buffers.each_value {|value| value.clear }
      @doc_name = doc_name
      @doc_count += 1
    end
#-------------------------------------------------------------------------------
    def end_document text
      @doc_buffers[:docs] << "#{@doc_count}\t'#{PGconn.escape_string(@doc_name)}'\t'#{PGconn.escape_string(text)}'\n"

      @doc_buffers.each {|key, value| @data_io[key] << value }
    end
#-------------------------------------------------------------------------------
# Tags
#-------------------------------------------------------------------------------
    def tag_name_id tag_name
      unless @known_tag_names.has_key? tag_name
        @tag_names_count += 1
        @doc_buffers[:tag_names] << "#{@tag_names_count}\t'#{PGconn.escape_string(tag_name)}'\n"
        @known_tag_names[tag_name] = @tag_names_count
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
      @doc_buffers[:tags] << "#{tag.id_tag}\t#{@doc_count}\t#{tag.id_tag_name}\t#{tag.tag_num}\t#{tag.parent_tag}\t#{tag.start_offset}\t#{tag.end_offset}\n"
    end
#-------------------------------------------------------------------------------
# Attributes
#-------------------------------------------------------------------------------
    def attribute_name_id attribute_name
      unless @known_attribute_names.has_key? attribute_name
        @attribute_names_count += 1
        @doc_buffers[:attribute_names] << "#{@attribute_names_count}\t'#{PGconn.escape_string(attribute_name)}'\n"
        @known_attribute_names[attribute_name] = @attribute_names_count
      end
      return @known_attribute_names[attribute_name]
    end
#-------------------------------------------------------------------------------
    def attribute_value_id attribute_value
      unless @known_attribute_values.has_key? attribute_value
        @attribute_values_count += 1
        @doc_buffers[:attribute_values] << "#{@attribute_values_count}\t'#{PGconn.escape_string(attribute_value)}'\n"
        @known_attribute_values[attribute_value] = @attribute_values_count
      end
      return @known_attribute_values[attribute_value]
    end
#-------------------------------------------------------------------------------
    def add_attribute tag_id, attribute_name_id, attribute_value_id
      @doc_buffers[:tag_attributes] << "#{tag_id}\t#{attribute_name_id}\t'#{attribute_value_id}'\n"
    end
#-------------------------------------------------------------------------------
# Index and tokens
#-------------------------------------------------------------------------------
    def token_id token
      unless @known_tokens.has_key? token
        @token_count += 1
        @doc_buffers[:tokens] << "#{@token_count}\t'#{PGconn.escape_string(token)}'\n"
        @known_tokens[token] = @token_count
      end
      return @known_tokens[token]
    end
#-------------------------------------------------------------------------------
    def add_token_index id_token, positions
      is_first = true
      array_string = "{"
      positions.each do |position|
        array_string += "," unless is_first
        is_first = false
        array_string += position.to_s
      end
      array_string += "}"
      
      @doc_buffers[:inverted_index] << "#{@doc_count}\t#{id_token}\t'#{array_string}'\n"
    end
  end

end
