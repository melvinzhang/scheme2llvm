BEGIN {
    count = 0
    max = 0
}

/^$/ {
    count++
    if (count > max) {
        exit
    }
}

{
    print
}
