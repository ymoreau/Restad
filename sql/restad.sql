--------------------------------------------------------------------------------
-- Returns the character offset beginning of the term_pos'th term in text
CREATE OR REPLACE FUNCTION get_offset(doctext text, term_pos int) RETURNS int AS $$
DECLARE
    tsdebug_row record;
    raw_text text := '';
    lexeme_count int := 0;
    term_offset int := 0;
BEGIN
    FOR tsdebug_row IN SELECT token,lexemes FROM ts_debug(doctext) LOOP
        IF tsdebug_row.lexemes IS NOT NULL THEN
            lexeme_count := lexeme_count + 1;
        END IF;
        IF lexeme_count = term_pos THEN
            RETURN char_length(raw_text);
        END IF;

        raw_text := raw_text || tsdebug_row.token;
    END LOOP;
    
    RETURN -1;
END
$$ LANGUAGE 'plpgsql';

--------------------------------------------------------------------------------
-- Returns a XPath-like string for the given tag_id
CREATE OR REPLACE FUNCTION xterm_path(iddoc int, idtag int) RETURNS text AS $$
  SELECT '/' || path FROM
    (WITH RECURSIVE pathto(path, idtag) AS (
      SELECT CAST(tag_name || '[' || tag_order_position::text || ']' AS TEXT), parent_id FROM tags NATURAL JOIN tag_names 
        WHERE id_doc = $1 AND id_tag = $2
      UNION
      SELECT CAST(names.tag_name || '[' || tags.tag_order_position::text || ']/' || pathto.path AS TEXT), parent_id
        FROM tags NATURAL JOIN tag_names AS names, pathto WHERE tags.id_doc = $1 AND tags.id_tag = pathto.idtag)
      SELECT * FROM pathto) AS pathto(path, idtag)
    WHERE idtag IS NULL;
$$ LANGUAGE 'sql';

--------------------------------------------------------------------------------
-- Returns the term positions of the given word for the given tsvector
CREATE OR REPLACE FUNCTION get_term_positions(word VARCHAR, tsvect tsvector) RETURNS TABLE(r_pos int) AS $$
DECLARE
    term text;
    str_positions text;
    pos_int integer;
BEGIN
    SELECT token INTO STRICT term FROM substring(to_tsvector(word)::text from '''(.+)''') as token;
    SELECT strpos INTO str_positions FROM substring(tsvect::text from '''' || term || ''':([0-9,]+)') as strpos;
    FOR pos_int IN SELECT pos_str::int FROM regexp_split_to_table(str_positions, ',') as pos_str LOOP
        r_pos := pos_int;
        RETURN NEXT;
    END LOOP;
    RETURN;
END
$$ LANGUAGE 'plpgsql';

--------------------------------------------------------------------------------
-- Returns the result_limit highest ranked documents for the given tsquery
CREATE OR REPLACE FUNCTION xdocs_rank(query tsquery, result_limit int default 1000) RETURNS TABLE(idoc int, tsrank float) AS $$
DECLARE
   docrow record;
BEGIN
    FOR docrow IN SELECT id_doc, ts_rank(text_tsvector, query) AS rank, text_tsvector, text FROM docs
            WHERE text_tsvector @@ query ORDER BY rank DESC LIMIT result_limit LOOP

        idoc := docrow.id_doc;
        tsrank := docrow.rank;
        RETURN NEXT;
    END LOOP;
    RETURN;
END
$$ LANGUAGE 'plpgsql';

--------------------------------------------------------------------------------
-- Returns the tag id of the LCA for the given term in the given document
CREATE OR REPLACE FUNCTION xterm_lca(qterm text, doc_id int) RETURNS TABLE(lca_tag_id int) AS $$
DECLARE
    docrow record;
    pos int;
    offset int;
BEGIN
    SELECT text, text_tsvector INTO STRICT docrow FROM docs WHERE id_doc = doc_id;
    FOR pos IN SELECT get_term_positions(qterm, docrow.text_tsvector) FROM docs WHERE id_doc = doc_id LOOP
        offset := get_offset(docrow.text, pos); -- Map to the offset position
        -- Get the nearest tag id for this term position in the current doc
        SELECT t.id_tag INTO lca_tag_id
          FROM (SELECT id_tag, parent_id FROM tags WHERE id_doc = doc_id AND
                starting_offset <= offset AND ending_offset > offset) AS t
          WHERE t.id_tag NOT IN 
              (SELECT parent_id FROM tags WHERE id_doc = doc_id AND
               parent_id IS NOT NULL AND starting_offset <= offset AND ending_offset > offset)
          ;
        RETURN NEXT;
    END LOOP;
    
    RETURN;
END
$$ LANGUAGE 'plpgsql';

