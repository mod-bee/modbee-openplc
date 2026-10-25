# Resources

Put the C/C++ libraries your blocks need in here, one folder each:

```
resources/
  MyLibrary/
    library.properties
    src/
      MyLibrary.h
      MyLibrary.cpp
```

That is the ordinary Arduino library layout, so in most cases you can copy a
library folder in as it stands. Build Settings, under Manifest in the project
tree, adds one for you and lists what is here.

Everything in here is packaged into the `.stlib` when you build. A project
that installs your library gets these sources unpacked into its own build and
compiled for its own target, so there is nothing for the user to install
separately and the sources can never fall out of step with your blocks.

## Notes

- Sources may nest as deeply as you like under `src/`.
- A folder without a `library.properties` still works; one is generated.
- A file sitting loose in `resources/`, outside any folder, belongs to no
  library and is skipped with a warning.
- Only text files are carried. Pre-compiled binaries are not.
