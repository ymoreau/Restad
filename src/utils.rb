#!/usr/bin/env ruby
# Utilities

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

module Restad
#===============================================================================
  class DBUtils
    BUFFER_SIZE = 4096
    MAX_TRIES = 4

#-------------------------------------------------------------------------------
# It assumes io is opened
    def self.sql_copy db, table_description, io, table_label = ""
      db.exec("COPY #{table_description} FROM STDIN WITH DELIMITER '\t' csv QUOTE ''''")

      begin
        buffer = ''
        while io.read(BUFFER_SIZE, buffer) 
          until db.put_copy_data(buffer) # Wait for writable connection
          end
        end
      rescue Errno => e
        db.put_copy_end(errmsg)
        raise e
      end
        
      db.put_copy_end
      while res = db.get_result
        raise PGError, "COPY failed for '#{table_label}'\n\t->#{res.result_error_message}" if res.result_status == PGresult::PGRES_FATAL_ERROR
      end
    end
#-------------------------------------------------------------------------------
    def self.next_id db, table_name
      res = db.exec("SELECT nextval('#{table_name}'::regclass)")
      return res.getvalue(0,0).to_i if res.ntuples == 1
      return -1
    end
  end
#===============================================================================
  class Utils
  # Return how much memory is using the process, in MB
    def self.used_memory
      map = `pmap -d #{Process.pid} | tail -n 1`
      raise RestadException, "empty pmap result" if map.empty?
      match_data = /^\w+:\s*(\d+)\w/.match(map)
      raise RestadException, "pmap result did not match the expected format" if match_data.nil?
      size = match_data.captures.first.to_i / 1024
      return size
    end
  end
#===============================================================================
  class RestadException < StandardError
  end

end

#===============================================================================
class String
  def clean!
    strip!
    gsub!(/\s+/, " ")
  end
#-------------------------------------------------------------------------------
  def strict_clean!
    strip!
    gsub!(/\s+/, "_")
    downcase!
  end
#-------------------------------------------------------------------------------
  def cut! length
    slice!(length, size - 1) if size > length
  end
end

#===============================================================================
class Time
  # Time elapsed since starting_time, in s
  def self.elapsed starting_time
    (Time.now - starting_time).round(3)
  end
end
