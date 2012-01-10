CREATE OR REPLACE FUNCTION xterm_match(qterm text, doc_id int) RETURNS TABLE(nearest_tag_id int) AS $$
DECLARE
    docrow record;
    pos int;
    offset int;
BEGIN
    SELECT text, text_tsvector INTO STRICT docrow FROM docs WHERE id_doc = doc_id;
    FOR pos IN SELECT get_term_positions(qterm, docrow.text_tsvector) FROM docs WHERE id_doc = doc_id LOOP
        offset := get_offset(docrow.text, pos); -- Map to the offset position
        -- Get the nearest tag id for this term position in the current doc
        SELECT t.id_tag INTO nearest_tag_id
          FROM (SELECT id_tag, parent_tag FROM tags WHERE id_doc = doc_id AND
                starting_offset <= offset AND ending_offset > offset) AS t
          WHERE t.id_tag NOT IN 
              (SELECT parent_tag FROM tags WHERE id_doc = doc_id AND
               parent_tag IS NOT NULL AND starting_offset <= offset AND ending_offset > offset)
          ;
        RETURN NEXT;
    END LOOP;
    
    RETURN;
END
$$ LANGUAGE 'plpgsql';
