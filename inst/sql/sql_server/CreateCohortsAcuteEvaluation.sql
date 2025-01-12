/************************************************************************
@file CreateCohortsAcuteEvaluation.sql
************************************************************************/

{DEFAULT @cdm_database_schema = 'CDM_SIM' }
{DEFAULT @cohort_database_schema = 'CDM_SIM' }
{DEFAULT @cohort_database_table = 'cohort'
{DEFAULT @x_spec_cohort = 0 }
{DEFAULT @tempDB = "scratch.dbo" }
{DEFAULT @test_cohort = "test_cohort" }
{DEFAULT @ageLimit = 0}
{DEFAULT @upperAgeLimit = 120}
{DEFAULT @gender = c(8507, 8532)}
{DEFAULT @race = 0}
{DEFAULT @ethnicity = 0}
{DEFAULT @startDate = '19000101' }
{DEFAULT @endDate = '21000101' }
{DEFAULT @baseSampleSize = 150000 }
{DEFAULT @xSpecSampleSize = 1500 }
{DEFAULT @mainPopnCohort = 0 }
{DEFAULT @mainPopnCohortStartDay = 0 }
{DEFAULT @mainPopnCohortEndDay = 0 }
{DEFAULT @exclCohort = 0 }
{DEFAULT @visitLength = 0 }
{DEFAULT @visitType = c(9201) }
{DEFAULT @firstCut = FALSE }

IF OBJECT_ID('tempdb..#cohort_person', 'U') IS NOT NULL
	DROP TABLE #cohort_person;

SELECT *
INTO #cohort_person
FROM (
	SELECT co.*,
		p.*,
		row_number() OVER (
			ORDER BY NewId()
			) rn
	FROM @cohort_database_schema.@cohort_database_table co
	JOIN @cdm_database_schema.person p
		ON co.subject_id = p.person_id
			AND year(COHORT_START_DATE) - year_of_birth >= @ageLimit
			AND year(COHORT_START_DATE) - year_of_birth <= @upperAgeLimit
			AND gender_concept_id IN (@gender)
			{@race != 0} ? {AND race_concept_id in (@race)}
      {@ethnicity != 0} ? {AND ethnicity_concept_id in (@ethnicity)}
	WHERE cohort_definition_id = @x_spec_cohort
		AND co.COHORT_START_DATE >= cast('@startDate' AS DATE)
		AND co.COHORT_START_DATE <= cast('@endDate' AS DATE)
	) pos;


IF OBJECT_ID('@tempDB.@test_cohort', 'U') IS NOT NULL
	DROP TABLE @tempDB.@test_cohort;

CREATE TABLE @tempDB.@test_cohort (
  cohort_definition_id bigint NOT NULL,
  subject_id bigint NOT NULL,
  cohort_start_date date,
  cohort_end_date date);

insert into @tempDB.@test_cohort (COHORT_DEFINITION_ID, SUBJECT_ID, COHORT_START_DATE, COHORT_END_DATE)
	select 0 as COHORT_DEFINITION_ID, person_id as SUBJECT_ID,
		dateadd(day, 0, visit_start_date) COHORT_START_DATE,
        dateadd(day, 1, visit_start_date) COHORT_END_DATE
    from (select
{@mainPopnCohort == 0} ? {
					v.person_id, FIRST_VALUE(visit_start_date) OVER (PARTITION BY v.person_id ORDER BY NewId()) visit_start_date,
						row_number() over (order by NewId()) rn
					from @cdm_database_schema.visit_occurrence v
	        JOIN @cdm_database_schema.observation_period obs
	          on v.person_id = obs.person_id
	            AND v.visit_start_date >= dateadd(d, 365, obs.observation_period_start_date)
		          AND v.visit_start_date <= dateadd(d, -30, obs.observation_period_end_date)
          join (
                select person_id,
                  datediff(day, min(observation_period_start_date), min(observation_period_end_date)) lenPd,
                  min(observation_period_start_date) observation_period_start_date,
                  min(observation_period_end_date) observation_period_end_date,
                  count(observation_period_id) cntPd
                from @cdm_database_schema.observation_period
                group by person_id) obs2
                on v.person_id = obs2.person_id
                  and v.visit_start_date >= obs2.observation_period_start_date
                  and v.visit_start_date <= obs2.observation_period_end_date
                  and lenPd >= 730
                  and cntPd = 1
					join @cdm_database_schema.person p
					  on v.person_id = p.person_id
						and year(visit_start_date) - year_of_birth >= @ageLimit
						and year(visit_start_date) - year_of_birth <= @upperAgeLimit
						and gender_concept_id in (@gender)
						{@race != 0} ? {AND race_concept_id in (@race)}
            {@ethnicity != 0} ? {AND ethnicity_concept_id in (@ethnicity)}
            join (
              select person_id,
                datediff(day, min(observation_period_start_date), min(observation_period_end_date)) lenPd,
                min(observation_period_start_date) observation_period_start_date,
                min(observation_period_end_date) observation_period_end_date,
                count(observation_period_id) cntPd
              from @cdm_database_schema.observation_period
              group by person_id) obs2
              on v.person_id = obs2.person_id
                and v.visit_start_date >= obs2.observation_period_start_date
                and v.visit_start_date <= obs2.observation_period_end_date
                and lenPd >= 730
                and cntPd = 1
{@exclCohort != 0} ? { -- exclude subjects in the xSens cohort
          left join @cohort_database_schema.@cohort_database_table excl
            on v.person_id = excl.subject_id
              and v.visit_start_date = excl.COHORT_START_DATE
          }
					where visit_start_date >= cast('@startDate' AS DATE)
						and visit_start_date <= cast('@endDate' AS DATE)
						and v.visit_concept_id in (@visitType)
						and datediff(day, visit_start_date, visit_end_date) >= @visitLength
{@firstCut} ? {and 11*(9*(v.visit_occurrence_id/9)/11) = v.visit_occurrence_id}
{@exclCohort != 0} ? { -- exclusion = did not match on the above left join
						and excl.subject_id is NULL
}
}
{@mainPopnCohort != 0} ? {
					--co.subject_id as person_id, v.visit_start_date,
					--	row_number() over (order by NewId()) rn

					co.subject_id as person_id, FIRST_VALUE(v.visit_start_date) OVER (PARTITION BY v.person_id ORDER BY NewId()) visit_start_date,
						row_number() over (order by NewId()) rn

					from @cohort_database_schema.@cohort_database_table co
					join @cdm_database_schema.visit_occurrence v
					  on v.person_id = co.subject_id
					    and v.visit_concept_id in (@visitType)
					    and v.visit_start_date >= dateadd(day, @mainPopnCohortStartDay, co.COHORT_START_DATE)
					    and v.visit_start_date <= dateadd(day, @mainPopnCohortEndDay, co.COHORT_START_DATE)
					    and v.visit_start_date >= cast('@startDate' AS DATE)
		          and v.visit_start_date <= cast('@endDate' AS DATE)
		       join (
              select person_id,
                datediff(day, min(observation_period_start_date), min(observation_period_end_date)) lenPd,
                min(observation_period_start_date) observation_period_start_date,
                min(observation_period_end_date) observation_period_end_date,
                count(observation_period_id) cntPd
              from @cdm_database_schema.observation_period
              group by person_id) obs2
              on v.person_id = obs2.person_id
                and v.visit_start_date >= obs2.observation_period_start_date
                and v.visit_start_date <= obs2.observation_period_end_date
                and lenPd >= 730
                and cntPd = 1
					join @cdm_database_schema.person p
					  on co.subject_id = p.person_id
						and  year(co.COHORT_START_DATE) - year_of_birth >= @ageLimit
						and year(co.COHORT_START_DATE) - year_of_birth <= @upperAgeLimit
						and gender_concept_id in (@gender)
						{@race != 0} ? {AND race_concept_id in (@race)}
            {@ethnicity != 0} ? {AND ethnicity_concept_id in (@ethnicity)}
						{@exclCohort != 0} ? {
          left join @cohort_database_schema.@cohort_database_table excl
            on v.person_id = excl.subject_id
              and v.visit_start_date = excl.COHORT_START_DATE
          }
					where co.cohort_definition_id = @mainPopnCohort
{@exclCohort != 0} ? {
						and excl.subject_id is NULL
}
}
	) negs
      where rn <= cast('@baseSampleSize' as bigint)
    union
      select 0 as COHORT_DEFINITION_ID, SUBJECT_ID, cp.COHORT_START_DATE COHORT_START_DATE,
        dateadd(day, 1, cp.COHORT_START_DATE) COHORT_END_DATE
      from #cohort_person cp
      join @cdm_database_schema.observation_period o
        on cp.SUBJECT_ID = o.person_id
          and cp.COHORT_START_DATE >= o.observation_period_start_date
          and cp.COHORT_START_DATE <= o.observation_period_end_date
      where rn <= @xSpecSampleSize
      union
      select @x_spec_cohort as COHORT_DEFINITION_ID, SUBJECT_ID, cp.COHORT_START_DATE COHORT_START_DATE,
        dateadd(day, 1, cp.COHORT_START_DATE) COHORT_END_DATE
      from #cohort_person cp
      join @cdm_database_schema.observation_period o
        on cp.SUBJECT_ID = o.person_id
          and cp.COHORT_START_DATE >= o.observation_period_start_date
          and cp.COHORT_START_DATE <= o.observation_period_end_date
      where rn <= @xSpecSampleSize
      ;
