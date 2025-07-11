#!/bin/bash

# Check if argument is provided
if [ $# -eq 0 ]; then
    echo "Usage: $0 \"number1 number2 number3 ...\""
    echo "Example: $0 \"1 2 3 4 5\""
    exit 1
fi

# Get the input string and convert to array
numbers_string="$1"
read -ra numbers <<< "$numbers_string"

# Initialize variables
mean=0
count=0

echo "Incremental mean calculation:"
echo "----------------------------"

# Process each number
for num in "${numbers[@]}"; do
    # Validate that it's a number
    if ! [[ "$num" =~ ^-?[0-9]+\.?[0-9]*$ ]]; then
        echo "Error: '$num' is not a valid number"
        exit 1
    fi
    
    # Increment count
    ((count++))
    
    # Calculate incremental mean: mean = mean + (new_value - mean) / count
    if [ $count -eq 1 ]; then
        mean=$num  # First number becomes the initial mean
    else
        mean=$(echo "scale=6; $mean + ($num - $mean) / $count" | bc -l)
    fi
    
    # Format output
    printf "After %d number(s): %.6f (added: %s)\n" "$count" "$mean" "$num"
done

echo "----------------------------"
printf "Final mean: %.6f\n" "$mean"
