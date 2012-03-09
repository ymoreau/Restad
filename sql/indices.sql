-- Table : docs
alter table docs add primary key(id_doc);

CREATE OR REPLACE FUNCTION update_tsvector() RETURNS trigger AS $$
begin
  new.text_tsvector := to_tsvector(new.text);
  return new;
end
$$ LANGUAGE plpgsql;

CREATE TRIGGER tsvectorupdate BEFORE INSERT OR UPDATE
ON docs FOR EACH ROW EXECUTE PROCEDURE update_tsvector();

CREATE INDEX doc_tsvector_idx ON docs USING gin (text_tsvector);

-- Table : tag_names
alter table tag_names add primary key(id_tag_name);
alter table tag_names add constraint tag_names_tag_name_key unique(tag_name);

-- Table : tags
alter table tags add constraint tags_id_doc_fkey foreign key (id_doc) references docs(id_doc) on delete cascade;
alter table tags add constraint tags_id_tag_name_fkey foreign key (id_tag_name) references tag_names(id_tag_name);

create index tags_id_doc_index on tags(id_doc);
create index tags_id_tag_index on tags(id_tag);
create index tags_id_tag_name_index on tags(id_tag_name);
create index tags_parent_index on tags(parent_id);

-- Table : attribute_names
alter table attribute_names add primary key(id_attribute_name);
alter table attribute_names add constraint attribute_names_attribute_name_key unique(attribute_name);

-- Table : tag_attributes
alter table tag_attributes add constraint tag_attributes_id_doc_fkey foreign key (id_doc) references docs(id_doc) on delete cascade;
alter table tag_attributes add constraint tag_attributes_id_attribute_name_fkey foreign key (id_attribute_name) references attribute_names(id_attribute_name);

create index attributes_id_doc_index on tag_attributes(id_doc);
create index attributes_id_tag_index on tag_attributes(id_tag);
create index attributes_id_attname_index on tag_attributes(id_attribute_name);
