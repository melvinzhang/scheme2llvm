BEGIN {
    show = 1
}

/^;>>>/ {
    show = 0
    print $0
    next
}

/^;<<</ {
    show = 1
    print $0
    next
}

{
    if (show) {
        print $0
    } else {
        print "; " $0
    }
}
