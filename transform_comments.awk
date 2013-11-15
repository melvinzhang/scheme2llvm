BEGIN {
    show = 1
}

/^;;;/ {
    show = 1 - show
    next
}

{
    if (show) {
        print $0
    } else {
        print "; " $0
    }
}
