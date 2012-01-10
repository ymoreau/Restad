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
