# tool_run_r_code rejects subprocess timeouts readably

    Code
      error
    Output
      <error/ellmer_tool_reject>
      Error in `ellmer::tool_reject()`:
      ! Tool call rejected. R code execution timed out after 0.05 seconds

# tool_run_bash rejects subprocess timeouts readably

    Code
      error
    Output
      <error/ellmer_tool_reject>
      Error in `ellmer::tool_reject()`:
      ! Tool call rejected. Command timed out after 0.05 seconds

# tool_run_r_code requires callr for process isolation

    Code
      tool_run_r_code("1 + 1")
    Condition
      Error in `rlang::check_installed()`:
      ! The package "callr" (>= 9999) is required to execute R code in a subprocess

