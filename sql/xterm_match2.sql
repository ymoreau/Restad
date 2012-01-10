CREATE OR REPLACE FUNCTION xterm_match2(qterm text, doc_id int) RETURNS TABLE(xpath text) AS $$
DECLARE
    nearest_tag_id int;
BEGIN
    FOR nearest_tag_id IN SELECT xterm_match(qterm, doc_id) LOOP
        xpath := get_path(nearest_tag_id);
        RETURN NEXT;
    END LOOP;
    
    RETURN;
END
$$ LANGUAGE 'plpgsql';
