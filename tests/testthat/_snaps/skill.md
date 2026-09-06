# Skill configuration is frozen and revised values retain defaults

    Code
      skill@name <- "changed"
    Condition
      Error:
      ! Cannot modify `name`: property is read-only after construction

---

    Code
      skill@prompt <- "changed"
    Condition
      Error:
      ! Cannot modify `prompt`: property is read-only after construction

---

    Code
      skill@path <- "elsewhere"
    Condition
      Error:
      ! Cannot modify `path`: property is read-only after construction

---

    Code
      S7::props(skill) <- list(version = "2.0.0")
    Condition
      Error:
      ! Cannot modify `version`: property is read-only after construction

---

    Code
      skill$requires$providers <- "openai"
    Condition
      Error:
      ! Can't set S7 properties with `$`. Did you mean `...@requires <- list(providers = "openai")`?

# Skill validates declarative fields before use

    Code
      Skill("")
    Condition
      Error in `validate_skill_text()`:
      ! `name` must be one non-empty string

---

    Code
      Skill("valid", version = NA_character_)
    Condition
      Error in `validate_skill_text()`:
      ! `version` must be one non-empty string

---

    Code
      Skill("valid", description = c("one", "two"))
    Condition
      Error in `validate_skill_text()`:
      ! `description` must be one string

---

    Code
      Skill("valid", prompt = function() "prompt")
    Condition
      Error in `validate_skill_text()`:
      ! `prompt` must be one string

---

    Code
      Skill("valid", tools = new.env())
    Condition
      Error in `Skill()`:
      ! `tools` must be a list

---

    Code
      Skill("valid", requires = "base")
    Condition
      Error in `validate_skill_requirements()`:
      ! `requires` must be a list

---

    Code
      Skill("valid", requires = list("base"))
    Condition
      Error in `validate_skill_requirements()`:
      ! `requires` must have unique non-empty names

---

    Code
      Skill("valid", requires = list(packages = "base", packages = "stats"))
    Condition
      Error in `validate_skill_requirements()`:
      ! `requires` must have unique non-empty names

---

    Code
      Skill("valid", requires = list(providers = new.env()))
    Condition
      Error in `validate_skill_requirement_data()`:
      ! `requires` must contain only declarative data, not executable or reference objects

---

    Code
      Skill("valid", requires = list(providers = NA_character_))
    Condition
      Error in `validate_skill_requirements()`:
      ! `requires$providers` must contain non-empty strings

---

    Code
      Skill("valid", requires = list(executable = function() NULL))
    Condition
      Error in `validate_skill_requirement_data()`:
      ! `requires` must contain only declarative data, not executable or reference objects

# Skill keeps executable state caller-owned across runtime consumers

    Code
      loaded$counter@name <- "changed"
    Condition
      Error:
      ! Cannot modify `name`: property is read-only after construction

---

    Code
      loaded$counter@prompt <- "changed"
    Condition
      Error:
      ! Cannot modify `prompt`: property is read-only after construction

# Skill boundaries reject legacy lookalikes

    Code
      skill_check_requirements(old)
    Condition
      Error in `skill_check_requirements()`:
      ! `skill` must be a Skill object

---

    Code
      agent$load_skill(old)
    Condition
      Error in `agent$load_skill()`:
      ! `skill` must be a Skill object or path to a skill directory

---

    Code
      validate_definition_registry(list(legacy = old), "skills")
    Condition
      Error in `validate_definition_registry()`:
      ! Invalid AgentDefinition file
      x Invalid object in `skills` registry
