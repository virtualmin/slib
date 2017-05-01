# slib
Library of POSIX shell functions used by Virtualmin install scripts.

This is a bundle of a bunch of functions used by virtualmin-install (and probably other installers in the future). Some of the bigger, more complex, functions have their own repo ([spinner](/swelljoe/spinner), [slog](/swelljoe/slog), and [run_ok](/swelljoe/run_ok), specifically), and are merged in here periodically. Unless you're building something very similar to the Virtualmin install script, you make want to pick and choose.

It is tested regularly on bash and dash. Other POSIX-y shells may or may not work.

# Usage

Source the library, and use its functions.

```bash
    . ./slib.sh

    # Log an error and output something about it to the user in red
    log_error "Oh no!"

    # Print a message, run a command, wait with a spinner, and print a status indicator,
    # in color and with Unicode fun.
    run_ok "touch somefile" "touching a file"

    # Use whatever package manager is available and install the named package
    # wait with a spinner, and print a status indicator in color.
    any_install "gcc"
```

Full docs will be written soon.
