#!/bin/bash

# Initialize variables
rotate=0
reset=0

# Parse options using a while loop and shift
while [[ "$#" -gt 0 ]]; do
    case $1 in
        -r|--rotate)
            rotate=1
            ;;
        --reset)
            reset=1
            ;;
        --) # End of all options
            shift
            break
            ;;
        -*|--*) # Invalid option
            echo "Unknown option: $1" >&2
            exit 1
            ;;
        *) # End of options, start of arguments
            break
            ;;
    esac
    shift
done

# Use the parsed options
echo "Rotate: $rotate"
echo "Reset: $reset"


# List the device ids and find the one with the stylus
stylus_id=$(xsetwacom --list | grep stylus | awk '{print $9}')
if [ $reset -eq 1 ]; then
    xsetwacom --set $stylus_id Rotate none
fi

if [ $rotate -eq 1 ]; then
    # Rotate it half
    xsetwacom --set $stylus_id Rotate half
fi


current_value=$(xsetwacom --get $stylus_id Rotate)

echo "Current value of Rotate for stylus is: ${current_value}"
