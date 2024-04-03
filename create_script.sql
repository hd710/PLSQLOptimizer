--drop tables
drop table user_dept    purge;
drop table item_loc_soh purge;
drop table item purge;
drop table loc  purge;
drop table item_loc_soh_hist purge;
--create item
create table item(
    item      varchar2(25) not null,
    dept      number(4)    not null,
    item_desc varchar2(25) not null
);

--create location
create table loc(
    loc      number(10)   not null,
    loc_desc varchar2(25) not null
);

--create location of the item and unit cost and stock on hand
create table item_loc_soh(
item          varchar2(25) not null,
loc           number(10)   not null,
dept          number(4)    not null,
unit_cost     number(20,4) not null,
stock_on_hand number(12,4) not null
)
;

-- 5. Create a new table that associates user to existing dept(s)
create table user_dept
(
 user_id   varchar2(50) not null,
 dept      number(4)    not null
);

--- in average this will take 1s to be executed
insert into item(item,dept,item_desc)
select level, round(DBMS_RANDOM.value(1,100)), translate(dbms_random.string('a', 20), 'abcXYZ', level) from dual connect by level <= 1000;

--- in average this will take 1s to be executed
insert into loc(loc,loc_desc)
select level+100, translate(dbms_random.string('a', 20), 'abcXYZ', level) from dual connect by level <= 100;

-- in average this will take less than 120s to be executed : have an error in tablespace:
--9	insert into item_loc_soh (item, loc, dept, unit_cost, stock_	ORA-01536: space quota exceeded for tablespace 'APEX_BIGFILE_INSTANCE_TBS4'
insert into item_loc_soh (item, loc, dept, unit_cost, stock_on_hand)
select item, loc, dept, (DBMS_RANDOM.value(5000,50000)), round(DBMS_RANDOM.value(1000,100000))
from item, loc;

commit;

---*1. Primary key definition and any other constraint or index suggestion
--Create primary key for item table to avoid create duplicate itens 
alter table item
add constraint item_pk primary key(item,dept)
enable novalidate;
--Create primary key for loc table to avoid create duplicate loc
alter table loc
add constraint loc_pk primary key(loc)
enable novalidate;
--Create primary key for item_loc_soh table to avoid duplicate item in the same location for the same department
alter table item_loc_soh
add constraint item_loc_soh_pk primary key(item, loc, dept)
enable novalidate;
--Create foreign key  item_fk 
--to enforce referential integrity and improve performance
alter table item_loc_soh
add constraint item_fk
foreign key (item,dept)
references item(item,dept);
--Create foreign key  loc_fk
alter table item_loc_soh
add constraint loc_fk
foreign key (loc)
references loc(loc);
--Create PK for user_dept table to avoid duplicate user id
alter table user_dept
add constraint user_pk primary key(user_id)
enable novalidate;

--exec dbms_stats.gather_table_stats(null, 'item_loc_soh');

--*2. Your suggestion for table data management and data access considering the application usage, for example, partition...
--Partition of loc and dept : the number of partitions is specified to X partitions
alter table item_loc_soh modify
partition by hash(loc,dept) partitions 4;

--*3. Suggestion to avoid row contention at table level parameter because of high level of concurrency
--Create index on the foreign key columns of the item_loc_soh table to avoid row contention at table level (3.) : avoid sessions blocked
--create the index local for this table, the database constructs the index equated for each partition
create index item_loc_soh_dept_idx on item_loc_soh(loc,dept) local;
--


--4. Create a view that can be used at screen level to show only the required fields
CREATE OR REPLACE FORCE EDITIONABLE VIEW "VW_ITEM_LOC_SOH" ("ITEM", "LOC", "DEPT", "UNIT_COST", "STOCK_ON_HAND") AS 
  SELECT /*+ INDEX(item_loc_soh item_loc_soh_dept_idx) */  item, loc, dept,unit_cost,stock_on_hand
    FROM   item_loc_soh;

/
create or replace  package "STOCK" as
--==============================================================================
--6. Create a package with procedure or function that can be invoked by store or all stores to save the item_loc_soh to a new table 
-------that will contain the same information plus the stock value per item/loc (unit_cost*stock_on_hand)
--==============================================================================
procedure process_hist_data (i_dept     in     number    default null,
							 i_item     in     varchar2  default null,
							 i_loc      in     number    default null);

/*
11. Create a program (plsql and/or java, or any other language) that can extract to a flat file (csv), 
---1 file per location: the item, department unit cost, stock on hand quantity and stock value.
----Creating the 1000 files should take less than 30s.
*/
procedure extract_csv_file(i_loc_in    in number,
                           i_loc_end   in number);


end "STOCK";
/
create or replace  package body "STOCK" as
--==============================================================================
-- Public API, see specification
--==============================================================================
procedure process_hist_data (i_dept     in     number    default null,
							 i_item     in     varchar2  default null,
							 i_loc      in     number    default null)
is
  l_sql_stat varchar2(1000);
  l_count    number;
begin
---invoked by store or all stores to save the item_loc_soh to a new table that will contain the same information plus the stock value per item/loc (unit_cost*stock_on_hand)
    --check if the table exists
    select count(1) into l_count from  user_tables where table_name='item_loc_soh_hist' ;
    --
    if l_count > 0 then 
        execute immediate 'drop table item_loc_soh_hist purge;';
    end if;
    --Create a new table that will contain the same information plus the stock value per item/loc (unit_cost*stock_on_hand)
    l_sql_stat:='create table item_loc_soh_hist
				as
				select 
                /*+ full(i) shared(i) */
				item ,
				loc ,
				dept ,
				unit_cost ,
				stock_on_hand,
				(unit_cost * stock_on_hand) as value_item_loc
				from item_loc_soh i
				where 1=1  ';
    --    
    if i_dept is not null then
       l_sql_stat := l_sql_stat || ' and dept =' || i_dept;
    end if; 
    --    
    if i_item is not null then
       l_sql_stat := l_sql_stat || ' and item =' || i_item;
    end if;	
	--    
    if i_loc is not null then
       l_sql_stat := l_sql_stat || ' and loc =' || i_loc;
    end if;

    --execute the sql statement    
    execute immediate l_sql_stat;   
exception
    when others then
        raise;
end process_hist_data;

procedure extract_csv_file(i_loc_in    in number,
                           i_loc_end   in number)
is
 --
 type rc_item_loc_soh is record
 (
 item          item_loc_soh.item%type,
 dept          item_loc_soh.dept%type,
 unit_cost     item_loc_soh.unit_cost%type,
 stock_on_hand item_loc_soh.stock_on_hand%type
 );
 type item_loc_soh_t is table of rc_item_loc_soh;
 l_item_loc_soh  item_loc_soh_t;
 --
 output          utl_file.file_type;
 filename        varchar2(200);
begin
  --
  select /*+ parallel */  
      item,
      dept, 
      sum(unit_cost)     unit_cost, 
      sum(stock_on_hand) stock_on_hand
      bulk collect into l_item_loc_soh 
        from item_loc_soh  where loc=i_loc_in
        group by item,dept;
   
    --rename the flat file
    filename := 'Flat_File_loc_' || i_loc_in ||'.csv';
    --Open the file
    output := utl_file.fopen('FLAT_FILE',filename,'w');
    --
    utl_file.put(output,'item,dept,unitCost,StockOnHand');
   --handle lines
   for i in 1..l_item_loc_soh.count
   loop
      utl_file.put_line(output,l_item_loc_soh(i).item ||','||l_item_loc_soh(i).dept||',' ||l_item_loc_soh(i).unit_cost ||','|| l_item_loc_soh(i).stock_on_hand);
   end loop;
    --close the file
    utl_file.fclose(output);
EXCEPTION
      WHEN utl_file.invalid_operation THEN
               Dbms_Output.Put_Line('Operação inválida no arquivo.');
               utl_file.fclose(output);
      WHEN utl_file.write_error THEN
               Dbms_Output.Put_Line('Erro de gravação no arquivo.');
               utl_file.fclose(output);
      WHEN utl_file.invalid_path THEN
               Dbms_Output.Put_Line('Diretório inválido.');
               utl_file.fclose(output);
      WHEN utl_file.invalid_mode THEN
               Dbms_Output.Put_Line('Modo de acesso inválido.');
               utl_file.fclose(output);
      WHEN Others THEN
               Dbms_Output.Put_Line('Problemas na geração do arquivo.');
               utl_file.fclose(output);
   
end extract_csv_file;


end "STOCK";
/


create or replace procedure run_task_parallel
authid current_user 
is
 task varchar2(30):='Create_Flat_File';
 plsql_stmt       varchar2(1000);
 l_chunk_sql      varchar2(1000);
begin
 --Create directory
 --CREATE DIRECTORY FLAT_FILE AS 'C:\Optimizer';
 --GRANT READ, WRITE ON DIRECTORY FLAT_FILE TO USER;
 --create the task
 dbms_parallel_execute.create_task(task_name => task);

  -- Chunk the table loc by loc
  l_chunk_sql := 'select loc , loc   from loc order by 1';
  dbms_parallel_execute.create_chunks_by_sql(task_name      => task, 
                                             sql_stmt       => l_chunk_sql,
                                             by_rowid       => false);                                          
 --
 plsql_stmt := 'begin  
                    stock.extract_csv_file(:start_id,:end_id);
                end;
                ';

 --run the task
 dbms_parallel_execute.run_task(
                                task_name      => task,
                                sql_stmt       => plsql_stmt,
                                language_flag  => dbms_sql.native,
                                parallel_level => 100
                               );       
 -- drop the task
 dbms_parallel_execute.drop_task(task_name      => task);
 
end run_task_parallel;

/
--Object Type location_ot/locations_nt
DROP TYPE location_ot FORCE;
/
DROP TYPE locations_nt FORCE;
/
CREATE TYPE location_ot AS OBJECT
(
   loc      number(10)   ,
   loc_desc varchar2(25) 
);

/
CREATE TYPE locations_nt AS TABLE OF location_ot;

/
--8. Create a pipeline function to be used in the location list of values (drop down)
create or replace function "GET_LOCATION_LIST"
return locations_nt 
pipelined
as
   type locations_at is table of loc%rowtype index by PLS_INTEGER;
   l_locations  locations_at;
begin
   ---8. Create a pipeline function to be used in the location list of values (drop down)
    select loc,loc_desc
    bulk collect into l_locations
    from loc ;

    --
    for i in 1..l_locations.count
    loop
       pipe row (
                location_ot (
                    l_locations(i).loc,
                    l_locations(i).loc_desc
                )
                );
    end loop;
    return;
exception
    when others then
        raise;
end "GET_LOCATION_LIST";
/