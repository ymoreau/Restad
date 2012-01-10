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

