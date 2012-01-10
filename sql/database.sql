--------------------------------------------------------------------------------
-- Table : docs
drop table if exists docs cascade;
create table docs
(
    id_doc int,
    doc_name varchar(256),
    text text,
    text_tsvector tsvector
);

--------------------------------------------------------------------------------
-- Table : tag_names
drop table if exists tag_names cascade;
create table tag_names
(
    id_tag_name int,
    tag_name varchar(256) --, unique(tag_name)
);

--------------------------------------------------------------------------------
-- Table : tags
drop table if exists tags cascade;
create table tags
(
    id_tag bigint,
    id_doc int, -- references docs(id_doc)
    id_tag_name int, -- references tag_names(id_tag_name)
    tag_num int not null,
    parent_tag int, -- References tags(id_tag)
    starting_offset int,
    ending_offset int
);

--------------------------------------------------------------------------------
-- Table : attribute_names
drop table if exists attribute_names cascade;
create table attribute_names
(
    id_attribute_name int,
    attribute_name varchar(256) -- unique(attribute_name)
);

--------------------------------------------------------------------------------
-- Table : attribute_values
drop table if exists attribute_values cascade;
create table attribute_values
(
    id_attribute_value int,
    attribute_value text -- unique(attribute_value)
);

--------------------------------------------------------------------------------
-- Table : tag_attributes
drop table if exists tag_attributes cascade;
create table tag_attributes
(
    id_tag bigint, -- references tags(id_tag)
    id_attribute_name int, -- references attribute_names(id_attribute_name)
    id_attribute_value int -- references attribute_values(id_attribute_value)
);

