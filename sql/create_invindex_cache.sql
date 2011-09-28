CREATE OR REPLACE FUNCTION create_invindex_cache() RETURNS VOID AS $$
DECLARE
    idtoken integer;
    iddoc integer;
    token_row inverted_index%rowtype;
    position integer;
    nearest_tag_id integer;
    nearest_tags_id_tmp integer[];
BEGIN
    -- For each token
    FOR idtoken IN SELECT id_token FROM tokens LOOP
        -- For each row in the inverted index, i.e. for each document containing the word
        FOR token_row IN SELECT * FROM inverted_index AS ii WHERE ii.id_token = idtoken LOOP
            iddoc := token_row.id_doc;

            -- For each position of the word
            FOR position IN SELECT unnest(token_row.positions) LOOP
                SELECT t.id_tag INTO nearest_tag_id
                  FROM (SELECT id_tag, parent_tag FROM tags WHERE id_doc = iddoc AND
                        starting_offset <= position AND ending_offset > position) AS t
                  WHERE t.id_tag NOT IN 
                      (SELECT parent_tag FROM tags WHERE id_doc = iddoc AND
                       parent_tag IS NOT NULL AND starting_offset <= position AND ending_offset > position)
                  ;
                SELECT nearest_tags_id_tmp || nearest_tag_id INTO nearest_tags_id_tmp;
            END LOOP;

            --RAISE NOTICE 'POSITIONS : %  --  TAGS : %', token_row.positions, nearest_tags_id_tmp;
            UPDATE inverted_index SET nearest_tags_id = nearest_tags_id_tmp WHERE id_doc = iddoc AND id_token = idtoken;
            nearest_tags_id_tmp := '{}';
        END LOOP;
    END LOOP;
END
$$ LANGUAGE 'plpgsql';
