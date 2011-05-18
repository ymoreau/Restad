CREATE OR REPLACE FUNCTION delete_document(doc_id integer) RETURNS void AS
$$
DECLARE
    doc_id_token integer;
    token_index_reference integer;
    doc_id_tag RECORD;
    tag_id_attribute RECORD;
    att_reference integer;
    tag_name_reference integer;
BEGIN
    -- Clean the no-longer used tokens
    FOR doc_id_token IN SELECT id_token FROM inverted_index WHERE id_doc = doc_id LOOP
        SELECT INTO token_index_reference id_token FROM inverted_index WHERE id_doc != doc_id AND id_token = doc_id_token LIMIT 1;
        IF NOT FOUND THEN
            DELETE FROM tokens WHERE id_token = doc_id_token; -- Delete the token
        END IF;
    END LOOP;

    -- Delete the index rows
    DELETE FROM inverted_index WHERE id_doc = doc_id;

    FOR doc_id_tag IN SELECT id_tag AS id, id_tag_name AS idname FROM tags WHERE id_doc = doc_id LOOP
        -- Clean the no-longer used attribute names and values
        FOR tag_id_attribute IN SELECT id_attribute_name AS idname, id_attribute_value AS idvalue FROM tag_attributes WHERE id_tag = doc_id_tag.id LOOP
            SELECT INTO att_reference id_attribute_name FROM tag_attributes WHERE id_tag != doc_id_tag.id AND id_attribute_name = tag_id_attribute.idname LIMIT 1;
            IF NOT FOUND THEN
                DELETE FROM attribute_names WHERE id_attribute_name = tag_id_attribute.idname;
            END IF;

            SELECT INTO att_reference id_attribute_value FROM tag_attributes WHERE id_tag != doc_id_tag.id AND id_attribute_value = tag_id_attribute.idvalue LIMIT 1;
            IF NOT FOUND THEN
                DELETE FROM attribute_values WHERE id_attribute_value = tag_id_attribute.idvalue;
            END IF;
        END LOOP;

        -- Delete the tag attributes
        DELETE FROM tag_attributes WHERE id_tag = doc_id_tag.id;

        -- Clean the no-longer used tag names
        SELECT INTO tag_name_reference id_tag_name FROM tags WHERE id_tag != doc_id_tag.id AND id_tag_name = doc_id_tag.idname LIMIT 1;
        IF NOT FOUND THEN
            DELETE FROM tag_names WHERE id_tag_name = doc_id_tag.idname;
        END IF;
    END LOOP;

    -- Delete the tags
    DELETE FROM tags WHERE id_doc = doc_id;

    -- Delete the document
    DELETE FROM docs WHERE id_doc = doc_id;
END;
$$ LANGUAGE plpgsql;
