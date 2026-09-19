# host edits are validated and bound to the executed receipt

    Code
      x$workflow$decide(x$owner, "approve", invalid)
    Condition
      Error in `study_validate()`:
      ! Unsupported outcome, units, method, population, or groups.

# denied computation and unauthorized callers produce no result

    Code
      x$workflow$view(stranger)
    Condition
      Error in `access()`:
      ! This requester is not authorized for the study workflow.

---

    Code
      x$workflow$decide(stranger, "approve")
    Condition
      Error in `access()`:
      ! This requester is not authorized for the study workflow.

# cancelled and unsupported proposals cannot reach computation

    Code
      x$workflow$decide(x$owner, "approve")
    Condition
      Error in `x$workflow$decide()`:
      ! The study was cancelled.

---

    Code
      proposal <- invalid$workflow$propose("study", invalid$owner)
    Message
      i Delegating to "analyst": Propose the study
    Condition
      Warning:
      Failed to evaluate 1 tool call.
      x [propose_analysis (call_fixture)]: Unsupported outcome, units, method, population, or groups.

---

    Code
      invalid$workflow$prepare(invalid$owner)
    Condition
      Error in `invalid$workflow$prepare()`:
      ! A fresh, valid proposal is required before preparing review.

# missing data revisions and malformed raw inputs fail before execution

    Code
      recipe$study_validate(plan, changed)
    Condition
      Error in `recipe$study_validate()`:
      ! The proposed dataset revision is unavailable or changed.

---

    Code
      recipe$study_validate(plan)
    Condition
      Error in `recipe$study_validate()`:
      ! Each analysis input must be one non-missing string.

---

    Code
      recipe$study_validate(plan)
    Condition
      Error in `recipe$study_validate()`:
      ! The analysis must specify exactly the supported input fields.

# rejected repeat proposals cannot relabel accepted provenance

    Code
      proposed <- workflow$propose("study", owner)
    Message
      i Delegating to "analyst": study
    Condition
      Warning:
      Failed to evaluate 1 tool call.
      x [propose_analysis (proposal_rejected)]: A proposal has already been recorded.

# failed preparation can be retried with the retained proposal

    Code
      x$workflow$prepare(x$owner)
    Condition
      Error in `req_perform_connection()`:
      ! HTTP 403 Forbidden.
      i fixture unavailable

# draft retries require no retained proposal and no cancellation

    Code
      x$workflow$propose("replace", x$owner)
    Condition
      Error in `x$workflow$propose()`:
      ! Start a new workflow for another proposal.

---

    Code
      x$workflow$propose("after cancel", x$owner)
    Condition
      Error in `x$workflow$propose()`:
      ! The study was cancelled.
