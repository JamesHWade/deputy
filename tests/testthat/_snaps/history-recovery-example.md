# invalid live configuration leaves the requested output path available

    Code
      sys.source(path, envir = new.env())
    Condition
      Error in `match.arg()`:
      ! 'arg' should be one of "original", "changed-constraint"
