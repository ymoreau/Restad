-- Primary keys
alter table tag_names add primary key (id_tag_name);
alter table attribute_names add primary key(id_attribute_name);
alter table attribute_values add primary key(id_attribute_value);
alter table docs add primary key (id_doc);
alter table tags add primary key (id_tag);
--alter table tag_attributes add primary key (id_tag, id_attribute_name);

-- Composed pk indexes
create index attributes_id_tag_index on tag_attributes(id_tag);
create index attributes_id_attname_index on tag_attributes(id_attribute_name);

-- Referencing key indexes
create index tags_id_doc_index on tags(id_doc);
create index tags_id_tag_name_index on tags(id_tag_name);
create index tags_parent_tag_index on tags(parent_tag);

-- Varchar indexes
create index tag_names_index on tag_names(tag_name);
create index attribute_names_index on attribute_names(attribute_name);

-- Fulltext index
UPDATE docs SET text_tsvector = to_tsvector(text); -- WORKAROUND
CREATE INDEX doc_tsvector_idx ON docs USING gin (text_tsvector);
