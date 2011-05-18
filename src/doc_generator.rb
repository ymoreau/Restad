#!/usr/bin/env ruby
# Document generator

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

require './utils.rb'

module Restad
#===============================================================================
  class TagData
    attr_reader :id, :name, :parent, :starting_offset, :ending_offset, :attributes_string

#-------------------------------------------------------------------------------
    def initialize id, name, parent, starting_offset, ending_offset, attribute_string
      @id = id
      @name = name
      @parent = parent
      @starting_offset = starting_offset
      @ending_offset = ending_offset
      @attribute_string = attribute_string # Must start with a space character
    end
#-------------------------------------------------------------------------------
    def starting_string
      return "<#{@name}#{@attribute_string}#{'/' if @starting_offset == @ending_offset}>"
    end
#-------------------------------------------------------------------------------
    def ending_string
      return "" if @starting_offset == @ending_offset
      return "</#{@name}>" # else
    end
  end
  
#===============================================================================
  class TagStatus
    OPENING_TAG = 0
    CLOSING_TAG = 1
    SELF_CLOSING_TAG = 2
  end

#===============================================================================
  class TagPosition
    attr_reader :position, :string, :tag_status

#-------------------------------------------------------------------------------
    def initialize position, string, tag_status
      @position = position
      @string = string
      @tag_status = tag_status
    end
  end

#===============================================================================
  class DocGenerator 
    attr_reader :doc_id, :output_path
    attr_writer :output_path
    
#-------------------------------------------------------------------------------
    def initialize db, output_path, doc_id = nil
      @db = db
      @output_path = output_path
      @doc_id = doc_id
    end
#-------------------------------------------------------------------------------
    def find_doc doc_name, path_joker = false
      doc_name = doc_name.gsub("'", "''")
      res = @db.exec("SELECT id_doc, doc_name FROM docs WHERE doc_name ILIKE '#{'%/' if path_joker}#{doc_name}'")
      if res.ntuples < 1
        puts "'#{doc_name}' not found in database."
      elsif res.ntuples > 1
        puts "More than 1 document found for this name."

        # Display the documents found
        count = 0
        docs = Hash.new
        res.each do |row|
          count += 1
          puts "[#{count}] (doc id : #{row['id_doc']}) '#{row['doc_name']}'"
          docs[count] = row['id_doc']
        end
        puts "[0] Cancel"

        # Ask the user which document to use
        print "Which document do you want to generate : "
        input = nil
        begin
          print "wrong input, try again : " unless input.nil?
          input = STDIN.gets
          input.chomp!.strip! unless input.nil?
          raise RestadException, "Aborted by user" if input == "0"
        end until input.nil? or docs.has_key?(input.to_i)
        @doc_id = docs[input.to_i]
      else
        @doc_id = res.getvalue(0,0)
      end
      return (not @doc_id.nil?)
    end
#-------------------------------------------------------------------------------
    def find_doc_name
      raise RestadException, "No document id/name is specified" if @doc_id.nil?

      res = @db.exec("SELECT doc_name FROM docs WHERE id_doc = #{@doc_id}")
      raise RestadException, "Document not found in database" if res.ntuples < 1
      res.getvalue(0,0)
    end
#-------------------------------------------------------------------------------
    def attribute_string tag_id
      str = ""
      res = @db.exec("SELECT attribute_name, attribute_value FROM tag_attributes NATURAL JOIN \
                attribute_names NATURAL JOIN attribute_values WHERE id_tag = #{tag_id}")
      res.each do |row|
        str << " #{row['attribute_name']}=\"#{row['attribute_value']}\""
      end
      return str
    end
#-------------------------------------------------------------------------------
    def generate_file indent_level, use_new_line, is_verbose, display_timing
      raise RestadException, "No doc specified" if @doc_id.nil?
      raise RestadException, "No output file specified" if @output_path.nil?

      output_file = File.open(@output_path, "w")

      time = Time.now
      # Get the raw text
      res = @db.exec("SELECT text FROM docs WHERE id_doc = #{@doc_id}")
      raise RestadException, "Doc with id #{@doc_id} not found" if res.ntuples == 0
      raise RestadException, "More than one doc with id #{@doc_id} were found" if res.ntuples > 1
      raw_text = res.getvalue(0,0)

      # Get the tags
      res = @db.exec("SELECT id_tag, tag_name, parent_tag, starting_offset, ending_offset \
              FROM tags NATURAL JOIN tag_names WHERE id_doc = #{@doc_id} ORDER BY starting_offset DESC")
      puts "Data read from database in #{Time.elapsed(time)}s" if display_timing
      doc_tags = Array.new
      res.each do |row|
        doc_tags << TagData.new(row['id_tag'].to_i, row['tag_name'], row['parent_tag'].to_i, \
                row['starting_offset'].to_i, row['ending_offset'].to_i, attribute_string(row['id_tag']))
      end
#      doc_tags.sort! {|a,b| a.starting_offset > b.starting_offset} # Already sorted by SQL query

      # Sort tags in appearance order
      tag_position_list = Array.new
      ending_tags_stack = Array.new
      until doc_tags.empty? do
        current_pos = doc_tags.last.starting_offset # Last tag has the lower starting offset
        consecutive_tags = Array.new
        until doc_tags.empty? or doc_tags.last.starting_offset != current_pos
          consecutive_tags.push(doc_tags.pop)
        end

        until consecutive_tags.empty? do
          consecutive_tags.each_index do |i|
            tag = consecutive_tags[i]
            parent_index = consecutive_tags.index {|t| t.id == tag.parent}
            if parent_index.nil? # tag has no parent in these consecutive tags
              # Add potential ending tags
              until ending_tags_stack.empty? or ending_tags_stack.last.position > tag.starting_offset
                tag_position_list.push(ending_tags_stack.pop)
              end

              # Add the next tag
              tag_status = TagStatus::OPENING_TAG
              if tag.starting_offset == tag.ending_offset
                tag_status = TagStatus::SELF_CLOSING_TAG if (consecutive_tags.index {|t| t.parent == tag.id}).nil?
              end
              tag_position_list.push(TagPosition.new(tag.starting_offset, tag.starting_string, tag_status))

              # Add the ending tag unless the tag was self-closing
              unless tag_status == TagStatus::SELF_CLOSING_TAG
                ending_tags_stack.push(TagPosition.new(tag.ending_offset, tag.ending_string, TagStatus::CLOSING_TAG))
              end

              consecutive_tags.delete_at(i)
              break
            end
          end
        end # until
      end # until

      # Add the last ending tags
      until ending_tags_stack.empty?
        tag_position_list.push(ending_tags_stack.pop)
      end

      # Generate the final xml string
      current_position = 0
      depth = 0
      xml_string = ""
      do_newline = false
      tag_position_list.each_index do |i|
        tag = tag_position_list[i]

        # Add the raw text until next tag
        slice_text = raw_text.slice(current_position, tag.position)
        unless slice_text.empty?
          xml_string << ' ' * (depth * indent_level) if do_newline # If last tag added a newline
          xml_string << slice_text
          xml_string << "\n" if use_new_line
        end

        if tag.tag_status == TagStatus::CLOSING_TAG
          depth -= 1
        end

        # Add the tag
        xml_string << ' ' * (depth * indent_level)
        xml_string << tag.string
        current_position = tag.position

        # Add a potentiel newline
        do_newline = false
        if tag.tag_status == TagStatus::SELF_CLOSING_TAG or tag.tag_status == TagStatus::CLOSING_TAG
          do_newline = true
        else
          depth += 1
        end
        if tag_position_list.size > i+1 and tag.position == tag_position_list[i+1].position
          do_newline = true
        end
        xml_string << "\n" if use_new_line and do_newline
      end # each_index
      xml_string << raw_text.slice(current_position, raw_text.size-1)

      output_file << xml_string
      puts "Document file was generated" if is_verbose
    end
  end

end
