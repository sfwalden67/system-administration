-- including OR REPLACE is more convenient when updating a subprogram
-- IN is the default for parameter declarations so it could be omitted
CREATE OR REPLACE PROCEDURE award_bonus (emp_id IN NUMBER, bonus_rate IN NUMBER)
  AS
-- declare variables to hold values from table columns, use %TYPE attribute
   emp_first_name        employees.first_name%TYPE;
   emp_last_name         employees.last_name%TYPE;
   emp_job_title         employees.job_title%TYPE;
   emp_sal         employees.salary%TYPE;
   emp_comm         employees.commission%TYPE;
-- declare an exception to catch when the salary is NULL
   salary_missing  EXCEPTION;
BEGIN  -- executable part starts here
-- select the column values into the local variables
   SELECT first_name,last_name,job_title,salary,commission INTO emp_first_name, emp_last_name, emp_job_title, emp_sal, emp_comm FROM employees
    WHERE employee_id = emp_id;
-- check whether the salary for the employee is null, if so, raise an exception
   IF emp_sal IS NULL THEN
     RAISE salary_missing;
   ELSE 
     IF emp_comm IS NULL THEN
-- if this is not a commissioned employee, increase the salary by the bonus rate
-- for this example, do not make the actual update to the salary
-- UPDATE employees SET salary = salary + salary * bonus_rate 
--   WHERE employee_id = emp_id;
       DBMS_OUTPUT.PUT_LINE('Employee ' || emp_id || ' receives a bonus: ' 
                            || TO_CHAR(emp_sal * bonus_rate) );
     ELSE
       DBMS_OUTPUT.PUT_LINE('Employee ' || emp_id 
                            || ' receives a commission. No bonus allowed.');
     END IF;
   END IF;
EXCEPTION  -- exception-handling part starts here
   WHEN salary_missing THEN
      DBMS_OUTPUT.PUT_LINE('Employee ' || emp_id || 
                           ' does not have a value for salary. No update.');
   WHEN OTHERS THEN
      NULL; -- for other exceptions do nothing
END award_bonus;