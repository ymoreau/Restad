SELECT id_doc, id_tag AS id, parent_id AS parent, tag_name AS name, starting_offset, ending_offset
  FROM tags NATURAL JOIN tag_names
  ORDER BY id_doc ASC, starting_offset ASC, parent_id ASC NULLS FIRST;
