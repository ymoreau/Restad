#!/usr/bin/env ruby
# Config file parser

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

require 'pg'
require './utils.rb'
require './parser.rb'

module Restad
#===============================================================================
  class ConfigParser
    
    DEFAULT_FILE = "./config"
    attr_reader :map

#-------------------------------------------------------------------------------
    def initialize file_path
      @map = Hash.new

      if not File.exist?(file_path) 
        if File.exist?(DEFAULT_FILE)
          print "Config file '#{file_path}' not found, use default '#{DEFAULT_FILE}' instead ? (y/n) "
          use_default = STDIN.gets
          use_default.chomp!.strip! unless use_default.nil?
          if use_default == "y"
            file_path = DEFAULT_FILE
          else
            file_path = nil
          end
        else
          puts "Config file '#{file_path}' not found. Default one will be created." 
          file_path = DEFAULT_FILE
        end
      end

      raise RestadException, "No config file error" if file_path.nil?
      @file_path = file_path

      # Read & store the config file
      if File.exist?(file_path)
        file = File.open(file_path, "r")

        file.each_line do |line|
          # Ignore comments
          if line.lstrip.index('#') == 0
            next
          end

          if line.include?('=')
            key, value = line.split('=')
            @map[key.strip] = value.strip
          end
        end
        file.close
      end
    end

#-------------------------------------------------------------------------------
    def add_parameter key, value
      return if @map.has_key?(key) or value.nil?

      file = File.open(@file_path, "a")
      file << "\n#{key} = #{value}"
      file.close
      @map[key] = value
    end
#-------------------------------------------------------------------------------
    def document_exploder
      document_tag = @map['document-tag']
      docname_attribute = @map['docname-attribute']
      docname_childtag = @map['docname-childtag']

      if document_tag.nil?
        print "Document root tag: "
        document_tag = STDIN.gets
        return nil if document_tag.nil?
        document_tag.chomp! 
        add_parameter("document-tag", document_tag)
      end
      if docname_attribute.nil? and docname_childtag.nil?
        puts "Name of the document can be a document root tag attribute or the content of a child of the root tag, or empty."
        print "Document name attribute (of document root tag) [optional]: "
        docname_attribute = STDIN.gets
        unless docname_attribute.nil?
          docname_attribute.chomp! 
          add_parameter("docname-attribute", docname_attribute)
        else
          print "Document name tag (child of document root tag) [optional]: "
          docname_childtag = STDIN.gets
          unless docname_childtag.nil?
            docname_childtag.chomp!
            add_parameter("docname-childtag", docname_childtag)
          end
        end
      end
      docname_childtag = nil unless docname_attribute.nil?

      return DocumentExploder.new(document_tag, docname_attribute, docname_childtag)
    end
#-------------------------------------------------------------------------------
    def database_connection
      if @map.has_key? "host"
        host = @map["host"]
      else
        print "Database host: "
        host = STDIN.gets
        host.chomp! unless host.nil?
        add_parameter("host", host)
      end
      
      if @map.has_key? "database"
        database = @map["database"]
      else
        print "Database name: "
        database = STDIN.gets
        database.chomp! unless database.nil?
        add_parameter("database", database)
      end

      if @map.has_key? "user"
        user = @map["user"]
      else
        print "User name: "
        user = STDIN.gets
        user.chomp! unless user.nil?
        add_parameter("user", user)
      end

      if @map.has_key? "password"
        password = @map["password"]
      else
        print "Password: "
        system "stty -echo" # Hide the console output
        password = STDIN.gets
        password.chomp! unless password.nil?
        system "stty echo"
        puts "" # Newline after password prompt
      end

      return PGconn.connect("host=#{host} dbname=#{database} user=#{user} password=#{password}")
    end
#-------------------------------------------------------------------------------
    def set_temporary_dir path
      return false if @map.has_key? "temp-dir"
      add_parameter("temp-dir", path)
      return true
    end
  end

end
