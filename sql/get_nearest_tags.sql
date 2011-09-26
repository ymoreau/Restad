DROP TYPE IF EXISTS nearest_tags CASCADE;
CREATE TYPE nearest_tags AS (id_doc INT, id_tag BIGINT);

CREATE OR REPLACE FUNCTION get_nearest_tags(word VARCHAR) RETURNS SETOF nearest_tags AS $$
DECLARE
    nearest_tag_values nearest_tags;
    idtoken integer;
    token_row inverted_index%rowtype;
    position integer;
BEGIN
    SELECT t.id_token INTO idtoken FROM tokens AS t WHERE word = t.token;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Word "%" not found', word;
    END IF;

    -- For each row in the inverted index, i.e. for each document containing the word
    FOR token_row IN SELECT * FROM inverted_index AS ii WHERE ii.id_token = idtoken LOOP
        nearest_tag_values.id_doc := token_row.id_doc;

        -- For each position of the word
        FOR position IN SELECT unnest(token_row.positions) LOOP
            --RAISE NOTICE 'DOC:% POS:%', token_row.id_doc, position;
            SELECT t.id_tag INTO nearest_tag_values.id_tag
              FROM (SELECT id_tag, parent_tag FROM tags WHERE id_doc = token_row.id_doc AND
                    starting_offset < position AND ending_offset > position) AS t
              WHERE t.id_tag NOT IN 
                  (SELECT parent_tag FROM tags WHERE id_doc = token_row.id_doc AND
                   parent_tag IS NOT NULL AND starting_offset < position AND ending_offset > position)
              ;
        END LOOP;

        RETURN NEXT nearest_tag_values;
    END LOOP;
    RETURN;
END
$$ LANGUAGE 'plpgsql';