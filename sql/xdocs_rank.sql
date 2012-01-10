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

