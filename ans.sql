-----  create a temp new session table for question 1.a, 1.b, and 3
CREATE TEMPORARY TABLE New_Session AS
with calendar_date_events as (with recursive calendar(date) as (values ('2019-01-01')
                                                                union all
                                                                select date(calendar.date, '+1 day') as date
                                                                from calendar
                                                                where calendar.date < '2019-01-31'),
                            user_play_events as (with startEvents as (select *
                                                                        from events
                                                                        where event_name like 'gameStarted'),
                                                    endEvents as (select *
                                                                    from events
                                                                    where event_name like 'gameEnded')
                                                select startEvents.user_id  as user_id,
                                                startEvents.session_id      as session_id,
                                                startEvents.event_timestamp as start_timestamp,
                                                endEvents.event_timestamp   as end_timestamp
                                                from startEvents
                                                join endEvents
                                                on startEvents.user_id = endEvents.user_id and
                                                startEvents.session_id = endEvents.session_id
                                                order by start_timestamp)
                                                select user_id,
                                                session_id,
                                                case
                                                when start_timestamp < calendar.date then datetime(calendar.date)
                                                else start_timestamp end as start_timestamp,
                                                case
                                                when end_timestamp > date(calendar.date, '+1 day')
                                                then datetime(calendar.date, '+1 day')
                                                else end_timestamp end   as end_timestamp,
                                                calendar.date as date
                                                from user_play_events
                                                 join calendar on calendar.date >= date(user_play_events.start_timestamp) and
                                                 calendar.date <= date(user_play_events.end_timestamp))
SELECT * FROM calendar_date_events;
-- add new date_column showing year-month-day, for later use
ALTER TABLE events ADD COLUMN new_timestamp;
UPDATE events SET new_timestamp = date(event_timestamp);

-- 1.a To return the daily active user
select date,count (distinct user_id) as DAU
from New_Session
group by date;

-- 1.b To return the weekly stickiness
with temp_table as (
with weekly_table as (select strftime('%W', date) as week_num,count (distinct user_id) as weekly_active
from New_Session 
group by strftime('%W', date))
SELECT t.date as date,t.daily_active as daily_active ,weekly_table.weekly_active as weekly_active
FROM (select distinct date,
        (strftime('%W', date)) as week_num,
       (select count( distinct user_id) from New_Session T2 where T2.date = T1.date) as daily_active
from New_Session T1) t
INNER JOIN weekly_table on weekly_table.week_num = t.week_num)
select *, ( CAST([daily_active] AS FLOAT) / [weekly_active]) as weekly_stickiness
from temp_table;

--2.a To return daily revenue 
select distinct  date(event_timestamp) as date,
       (select sum(transaction_value)) as revenue
from events 
GROUP BY
date(event_timestamp);

--2.b To return daily conversion rate
with temp_table as (with paied_user_table as (select distinct date(event_timestamp) as date,count(distinct user_id) as paied_user
from events
where transaction_id is not NULL
group by
date(event_timestamp))
select d.date as date,d.DAU as daily_active_user ,paied_user_table.paied_user as paied_user
from (select date,count (distinct user_id) as DAU
from New_Session
group by date) d 
INNER JOIN paied_user_table on paied_user_table.date = d.date)
select date, ( CAST([paied_user] AS FLOAT) / [daily_active_user]) as daily_conversion_rate
from temp_table;

--3. To return average daily playtime
select date,
sum((julianday(end_timestamp) - julianday(start_timestamp)) * 24 * 60) / count(distinct user_id) as average_minutes_played
from New_Session
group by date;
    
--4.a To return the CPI(Cost Per Install) per acquisition channel.  
SELECT a.[source ] as install_channel,a.date as install_date ,a.cost as CPI,e.user_id as install_user
FROM acquisition a
INNER JOIN events e on e.acquisition_channel = a.[source ] AND e.new_timestamp = a.date;


--4.b Using all available data, what acquisition channel should we focus on?  
--fisrt, lets see the cost table from the below query
select distinct [source ],
       (select sum(cost) from (SELECT [source ],date,cost
FROM acquisition a 
INNER JOIN events e on e.acquisition_channel = a.[source ] AND e.new_timestamp = a.date) T2 where T2.[source ] = T1.[source ]) as cost,
(select count([source ]) from (SELECT [source ],date,cost
FROM acquisition a 
INNER JOIN events e on e.acquisition_channel = a.[source ] AND e.new_timestamp = a.date) T2 where T2.[source ] = T1.[source ]) as source_count
from (SELECT [source ],date,cost
FROM acquisition a 
INNER JOIN events e on e.acquisition_channel = a.[source ] AND e.new_timestamp = a.date) T1;

--second, lets see the revenue table from the below query
select distinct acquisition_channel as source,
 (select max(revenue) from (select  T1.acquisition_channel, 
 (select sum(transaction_value) from events T2 where ( T2.user_id = T1.user_id ))as revenue
from events T1
where (T1.acquisition_channel in ("google_adwords","itunes","facebook") )) t2 where t2.acquisition_channel = t1.acquisition_channel) as max_payment,
 (select avg(revenue) from (select  T1.acquisition_channel, 
 (select sum(transaction_value) from events T2 where ( T2.user_id = T1.user_id ))as revenue
from events T1
where (T1.acquisition_channel in ("google_adwords","itunes","facebook") )) t2 where t2.acquisition_channel = t1.acquisition_channel  AND t2.revenue >0) as mean_payment,
 (select count(acquisition_channel) from (select  T1.acquisition_channel, 
 (select sum(transaction_value) from events T2 where ( T2.user_id = T1.user_id ))as revenue
from events T1
where (T1.acquisition_channel in ("google_adwords","itunes","facebook") )) t2 where t2.acquisition_channel = t1.acquisition_channel AND t2.revenue >0) as paied_user,
 (select sum(revenue) from (select  T1.acquisition_channel, 
 (select sum(transaction_value) from events T2 where ( T2.user_id = T1.user_id ))as revenue
from events T1
where (T1.acquisition_channel in ("google_adwords","itunes","facebook") )) t2 where t2.acquisition_channel = t1.acquisition_channel) as revenue
from (select  T1.acquisition_channel, 
 (select sum(transaction_value) from events T2 where ( T2.user_id = T1.user_id ))as revenue
from events T1
where (T1.acquisition_channel in ("google_adwords","itunes","facebook") )) t1;

--Finally, lets combine "cost table" and "revenue table"
select *, revenue-cost as "net_revenue = revenue-cost"
from (SELECT
    ta.source, 
    ta.cost,
    ta.download_from_source,
    tb.max_payment,
    tb.mean_payment,
    tb.paied_user,
    tb.revenue
FROM
    (select distinct [source ] as source,
       (select sum(cost) from (SELECT [source ],date,cost
FROM acquisition a 
INNER JOIN events e on e.acquisition_channel = a.[source ] AND e.new_timestamp = a.date) T2 where T2.[source ] = T1.[source ]) as cost,
(select count([source ]) from (SELECT [source ],date,cost
FROM acquisition a 
INNER JOIN events e on e.acquisition_channel = a.[source ] AND e.new_timestamp = a.date) T2 where T2.[source ] = T1.[source ]) as download_from_source
from (SELECT [source ],date,cost
FROM acquisition a 
INNER JOIN events e on e.acquisition_channel = a.[source ] AND e.new_timestamp = a.date) T1) ta
LEFT JOIN
    (select distinct acquisition_channel as source,
 (select max(revenue) from (select  T1.acquisition_channel, 
 (select sum(transaction_value) from events T2 where ( T2.user_id = T1.user_id ))as revenue
from events T1
where (T1.acquisition_channel in ("google_adwords","itunes","facebook") )) t2 where t2.acquisition_channel = t1.acquisition_channel) as max_payment,
 (select avg(revenue) from (select  T1.acquisition_channel, 
 (select sum(transaction_value) from events T2 where ( T2.user_id = T1.user_id ))as revenue
from events T1
where (T1.acquisition_channel in ("google_adwords","itunes","facebook") )) t2 where t2.acquisition_channel = t1.acquisition_channel  AND t2.revenue >0) as mean_payment,
 (select count(acquisition_channel) from (select  T1.acquisition_channel, 
 (select sum(transaction_value) from events T2 where ( T2.user_id = T1.user_id ))as revenue
from events T1
where (T1.acquisition_channel in ("google_adwords","itunes","facebook") )) t2 where t2.acquisition_channel = t1.acquisition_channel AND t2.revenue >0) as paied_user,
 (select sum(revenue) from (select  T1.acquisition_channel, 
 (select sum(transaction_value) from events T2 where ( T2.user_id = T1.user_id ))as revenue
from events T1
where (T1.acquisition_channel in ("google_adwords","itunes","facebook") )) t2 where t2.acquisition_channel = t1.acquisition_channel) as revenue
from (select  T1.acquisition_channel, 
 (select sum(transaction_value) from events T2 where ( T2.user_id = T1.user_id ))as revenue
from events T1
where (T1.acquisition_channel in ("google_adwords","itunes","facebook") )) t1) tb
USING(source));
--please see comments for this in report

--5. To return per install date, the average LTV and average time to first purchase.  
with LTV_table as (with temp_3 as (with temp_2 as (with temp_1 as (with temp_table as (with trans_table as (select * 
from events
where transaction_id is not NULL)
select i.install_day,trans_table.user_id,trans_table.new_timestamp as trans_date,trans_table.transaction_value as trans_value
from trans_table
inner join (select user_id,new_timestamp as install_day
from events
where event_name = "install") i on i.user_id = trans_table.user_id)
select *
from temp_table
where julianday(trans_date) - julianday(install_day) >=0)
select  distinct install_day ,user_id,sum(trans_value) as total_revenue_person
from temp_1
group by
user_id)
select distinct install_day,sum(total_revenue_person) as total_revenue_per_install_day,count (distinct user_id) as user_num
from temp_2
group by
install_day)
select install_day,total_revenue_per_install_day/user_num as average_LTV
from temp_3)
select a.install_day as install_day,LTV_table.average_LTV as average_LTV,a.average_time_till_first_purchase as "average_first_purchase(day)"
from LTV_table
inner join (with first_time_purchase_table as (with temp1_table as(with temp_table as (with trans_table as (select * 
from events
where transaction_id is not NULL)
select i.install_day,trans_table.user_id,trans_table.new_timestamp as trans_date
from trans_table
inner join (select user_id,new_timestamp as install_day
from events
where event_name = "install") i on i.user_id = trans_table.user_id)
select *,julianday(trans_date) - julianday(install_day) as gap
from temp_table
where julianday(trans_date) - julianday(install_day) >=0)
select *
from (select * from temp1_table order by user_id,gap desc)
group by user_id)
select distinct install_day , avg(gap) as average_time_till_first_purchase
from first_time_purchase_table
group by 
install_day) a on a.install_day=LTV_table.install_day;
