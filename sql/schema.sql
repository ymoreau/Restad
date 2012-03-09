
CREATE LANGUAGE plpgsql;

--------------------------------------------------------------------------------
-- Table : docs
drop table if exists docs cascade;
create table docs
(
    id_doc serial,
    doc_name varchar(256),
    text text,
    text_tsvector tsvector
);

--------------------------------------------------------------------------------
-- Table : tag_names
drop table if exists tag_names cascade;
create table tag_names
(
    id_tag_name serial,
    tag_name varchar(256)
);

--------------------------------------------------------------------------------
-- Table : tags
drop table if exists tags cascade;
create table tags
(
    id_doc int not null,
    id_tag int not null,
    id_tag_name int,
    tag_order_position int not null,
    parent_id int,
    starting_offset int,
    ending_offset int
);

--------------------------------------------------------------------------------
-- Table : attribute_names
drop table if exists attribute_names cascade;
create table attribute_names
(
    id_attribute_name serial,
    attribute_name varchar(256)
);

--------------------------------------------------------------------------------
-- Table : tag_attributes
drop table if exists tag_attributes cascade;
create table tag_attributes
(
    id_doc int not null,
    id_tag int not null, 
    id_attribute_name int,
    attribute_value text
    -- primary key(id_tag,id_doc)
);

