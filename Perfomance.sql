## Should Have
### Performance
9. Looking into the following explain plan what should be your recommendation and implementation to improve the existing data model. 
----------------------------------------------------------------------------------------------
Without performance changes

explain plan for
select * from ITEM_LOC_SOH where LOC=652 AND DEPT=68;

Plan hash value: 1697218418
 
----------------------------------------------------------------------------------
| Id  | Operation         | Name         | Rows  | Bytes | Cost (%CPU)| Time     |
----------------------------------------------------------------------------------
|   0 | SELECT STATEMENT  |              |  1080 |   109K| 10923   (3)| 00:00:01 |
|*  1 |  TABLE ACCESS FULL| ITEM_LOC_SOH |  1080 |   109K| 10923   (3)| 00:00:01 |
----------------------------------------------------------------------------------
 
Predicate Information (identified by operation id):
---------------------------------------------------
 
   1 - filter("LOC"=652 AND "DEPT"=68)
 
Note
-----
   - dynamic statistics used: dynamic sampling (level=2)

----*********Suggestion 
--Partition of dept : the number of partitions is specified to X partitions
alter table item_loc_soh modify
partition by hash(loc,dept) partitions 4;

--create the index local for this table, the database constructs the index equated for each partition
create index item_loc_soh_dept_idx on item_loc_soh(loc,dept) local;

explain plan for
 select /*+ INDEX(item_loc_soh item_loc_soh_dept_idx) */ * from ITEM_LOC_SOH where LOC=652 AND DEPT=68;
 
SET LINESIZE 130
SET PAGESIZE 0
SELECT * 
FROM   TABLE(DBMS_XPLAN.DISPLAY);

Plan hash value: 3137684299
 
------------------------------------------------------------------------------------------------------------------------------------
| Id  | Operation                                  | Name                  | Rows  | Bytes | Cost (%CPU)| Time     | Pstart| Pstop |
------------------------------------------------------------------------------------------------------------------------------------
|   0 | SELECT STATEMENT                           |                       |    91 |  9464 |    96   (0)| 00:00:01 |       |       |
|   1 |  PARTITION HASH SINGLE                     |                       |    91 |  9464 |    96   (0)| 00:00:01 |     8 |     8 |
|   2 |   TABLE ACCESS BY LOCAL INDEX ROWID BATCHED| ITEM_LOC_SOH          |    91 |  9464 |    96   (0)| 00:00:01 |     8 |     8 |
|*  3 |    INDEX RANGE SCAN                        | ITEM_LOC_SOH_DEPT_IDX |    91 |       |     6   (0)| 00:00:01 |     8 |     8 |
------------------------------------------------------------------------------------------------------------------------------------
 
Predicate Information (identified by operation id):
---------------------------------------------------
 
   3 - access("LOC"=652 AND "DEPT"=68)
 
Note
-----
   - dynamic statistics used: dynamic sampling (level=2)
 
  
 10. Run the previous method that was created on 6. for all the stores from item_loc_soh to the history table. 
     ---The entire migration should not take more than 10s to run (don't use parallel hint to solve it :)) 
	 
	=> See procedure stock.process_hist_data;
	
 11. Please have a look into the AWR report (AWR.html) in attachment and let us know what is the problem that the AWR is highlighting and potential solution.
 There are many sections of the report, I''ll focus in :
 1. DB Time
				Snap Id	Snap Time			Sessions	Cursors/Session
	Begin Snap:	15178	02-Jun-23 11:00:02	95			23.8
	End Snap:	15179	02-Jun-23 12:00:06	91			21.9
	Elapsed:	 		60.07 (mins)	 	 
	DB Time:	 		3,081.56 (mins)	 	 
	
 2. Instance efficiency
 3. Top 10 foreground events by wait Time
 

## Nice to have
### Performance
11. Create a program (plsql and/or java, or any other language) that can extract to a flat file (csv), 
1 file per location: the item, department unit cost, stock on hand quantity and stock value.
Creating the 1000 files should take less than 30s.
 
 => See procedure run_task_parallel

