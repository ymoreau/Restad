
CREATE LANGUAGE plpgsql;

--------------------------------------------------------------------------------
-- Table : docs
drop table if exists docs cascade;
create table docs
(
    id_doc serial,
    doc_name varchar(256),
    text text,
    text_tsvector tsvector,
    primary key(id_doc)
);

CREATE OR REPLACE FUNCTION update_tsvector() RETURNS trigger AS $$
begin
  new.text_tsvector := to_tsvector(new.text);
  return new;
end
$$ LANGUAGE plpgsql;

CREATE TRIGGER tsvectorupdate BEFORE INSERT OR UPDATE
ON docs FOR EACH ROW EXECUTE PROCEDURE update_tsvector();

CREATE INDEX doc_tsvector_idx ON docs USING gin (text_tsvector);

--------------------------------------------------------------------------------
-- Table : tag_names
drop table if exists tag_names cascade;
create table tag_names
(
    id_tag_name serial,
    tag_name varchar(256) unique, 
    primary key(id_tag_name)
);

--create index tag_names_index on tag_names(tag_name);

--------------------------------------------------------------------------------
-- Table : tags
drop table if exists tags cascade;
create table tags
(
    id_doc int references docs(id_doc) on delete cascade,
    id_tag int not null,
    id_tag_name int references tag_names(id_tag_name),
    tag_order_position int not null,
    parent_id int,
    starting_offset int,
    ending_offset int
    -- primary key(id_tag,id_doc)
);

create index tags_id_doc_index on tags(id_doc);
create index tags_id_tag_index on tags(id_tag);
create index tags_id_tag_name_index on tags(id_tag_name);
create index tags_parent_index on tags(parent_id);

--------------------------------------------------------------------------------
-- Table : attribute_names
drop table if exists attribute_names cascade;
create table attribute_names
(
    id_attribute_name serial,
    attribute_name varchar(256) unique,
    primary key(id_attribute_name)
);

--create index attribute_names_index on attribute_names(attribute_name);

--------------------------------------------------------------------------------
-- Table : tag_attributes
drop table if exists tag_attributes cascade;
create table tag_attributes
(
    id_doc int references docs(id_doc) on delete cascade,
    id_tag int not null, 
    id_attribute_name int references attribute_names(id_attribute_name),
    attribute_value text
    -- primary key(id_tag,id_doc)
);

create index attributes_id_doc_index on tag_attributes(id_doc);
create index attributes_id_tag_index on tag_attributes(id_tag);
create index attributes_id_attname_index on tag_attributes(id_attribute_name);

