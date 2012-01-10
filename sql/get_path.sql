CREATE OR REPLACE FUNCTION get_path(id INTEGER) RETURNS TEXT AS $$
  SELECT '/' || path FROM
    (WITH RECURSIVE pathto(path, id) AS (
      SELECT CAST(tag_name || '[' || tag_num::text || ']' AS TEXT), parent_tag FROM tags NATURAL JOIN tag_names WHERE id_tag = $1
      UNION
      SELECT CAST(names.tag_name || '[' || tags.tag_num::text || ']/' || pathto.path AS TEXT), parent_tag
        FROM tags NATURAL JOIN tag_names AS names, pathto WHERE tags.id_tag = pathto.id)
      SELECT * FROM pathto) AS pathto(path, id)
    WHERE id IS NULL;
$$ LANGUAGE 'sql';
