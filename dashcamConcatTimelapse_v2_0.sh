#!/bin/bash

#author: hyraxai
#date: 2020-09-15
#verion: 2.0

#helper text
usage="Usage:
script.sh [-h] [-c N] [-p ultrafast] [-s N] -- script to automate dashcam concatenation and timelapsing

where:
    -h  show this help text
    -c  Optional. Constant Rate Factor (CRF); set to an integer of 0-51. Higher numbers indicate lower quality and smaller output size. Recommended 17-18.
    -p  Optional. Default preset is medium. Otherwise, choose from ONE of the following:
            - ultrafast
            - superfast
            - veryfast
            - faster
            - fast
            - slow
            - slower
            - veryslow
    -s  Required. Speed muliplier of the outputted timelapse. If you do not want a timelapse, but just want to make one big file, set 0 here- all other muxing steps will be skipped.
    
            |-------------------------------------|
            |Input | Playback Speed | Frames Kept |
            |-------------------------------------|
            |2     | 2x             | 50%         |
            |5     | 5x             | 20%         |
            |10    | 10x            | 10%         |
            |20    | 20x            | 5%          |
            |100   | 100x           | 1%          |
            |-------------------------------------|
            
    
Example:
$ script.sh -c 18 -p slow -s 100
"

#set some global variables
dirTime=$(echo $(date +%Y%m%d_%H%M%S))
export finalProduct=./$dirTime/final/timelapse.mp4
export preparedTransportStreamIn=./$dirTime/tmp/concatOutput.mp4
presets=( "ultrafast" "superfast" "veryfast" "faster" "fast" "slow" "slower" "veryslow" ) 

#FUNCTIONS
#input validation
function main () {
    validate_input

    #get start time of preparation activities for timer report
    prepStart=`date +%s`

    #make a working directory and prep logging
    mkdir ./$dirTime
    mkdir ./$dirTime/tmp
    touch ./$dirTime/tmp/prep.log

    extract_ts
    concatPrep
    concatenate

    #make final directory for completed files
    mkdir ./$dirTime/final

    #set end time of preparation activities, do dumb time things
    prepEnd=`date +%s`
    prepRunTime=$((prepEnd-prepStart)) 

    #get start time of timelapse creation
    timelapseStart=`date +%s`

    #prep logging of muxing
    touch ./$dirTime/tmp/mux.log

    timelapse_speed $speed
    create_timelapse

    #set end time of timelapse creation, do stupid time things
    timelapseEnd=`date +%s`
    timelapseRunTime=$((timelapseEnd-timelapseStart)) 

    generate_report

    cleanup
}

function get_opts () {
    while getopts ":s:c:p:h" opt; do
        case $opt in
            h)  printf "%s\n" "$usage"
                exit
                ;;
            c)  compressionFactor=$OPTARG;;
            p)  preset=$OPTARG;;
            s)  speed=$OPTARG;;
            \?) printf "[!] Invalid option.\n"
                printf "%s\n" "$usage"
                exit
                ;;
        esac
    done

}
function validate_input () {
    while [[ -z ${checksComplete} ]]; do
    checksComplete=0
    inputErrors=0
        if [[ -z ${speed} ]]; then
            printf "[!] You didn't set a timelapse speed.\n\n"
            inputErrors=$((inputErrors+1))
            checksComplete=$((checksComplete+1))
        fi

        if [[ ! -z ${compressionFactor} ]]; then
            if (( "$compressionFactor" > 51 )); then
            printf "[!] Your Constant Rate Factor set too high. Please select a number lower than 51.\n\n"
            inputErrors=$((inputErrors+1))
            fi
        fi

        if [[ ! -z ${preset} ]]; then
            while [[ -z ${presetCheck} ]]; do
                for i in "${presets[@]}"; do
                    if [[ $i = "$preset" ]]; then
                        presetMatch=true
                        presetCheck=true
                        break
                    fi
                done
                if [[ -z ${presetMatch} ]]; then
                    printf "[!] There is a typo in your string selection, or you're making stuff up.\n\n"
                    inputErrors=$((inputErrors+1))
                    checksComplete=$((checksComplete+1))
                    break
                fi
            done
        fi

        if [[ ! -z ${speed} ]]; then
            if (( "$speed" > 1000 )); then
                printf "[!] Your timelapse speed is unconscionably high. If you really want to have an epileptic seisure, hack this script you animal you.\n\n"
                inputErrors=$((inputErrors+1))
                checksComplete=$((checksComplete+1))
            fi
        fi

    if [[ "$inputErrors" = 0 ]]; then
        printf "[OK] Input Validated.\n"
    elif [[ "$checksComplete" > 0 ]]; then
            printf "[!] You had $inputErrors Error(s) in your input. Please review errors above. Run -h to view help text.\n"
            exit
    fi
    done
}

#convert human speed input to decimal
function timelapse_speed () {
    frameRate=$(echo $(awk "BEGIN{print $1**-1}"))
}

#extracts transport stream of dashcam video files
function extract_ts () {
    printf "[-] Extracting transport streams...\n"
    for f in *.MOV; do
        ffmpeg -i $f -c copy -bsf:v h264_mp4toannexb -f mpegts ./$dirTime/tmp/$f.ts 2>>./$dirTime/tmp/prep.log
    done
    printf "[OK] Done.\n"
}

#generates formatted file list for concat command
function concatPrep () {
concatIn=$(echo $(ls ./$dirTime/tmp/*.ts) | sed -e "s/ /|/g") 
}

#concatenate transport streams into one file
function concatenate () {
    printf "[-] Concatinating transport streams to bulk MP4 container...\n"
    ffmpeg -i "concat:$concatIn" -c copy -bsf:a aac_adtstoasc $preparedTransportStreamIn 2>>./$dirTime/tmp/prep.log
    printf "[OK] Done. \n"
}

#this function does more rediculous time things
function show_time () {
    num=$1
    min=0
    hour=0
    day=0
    if((num>59));then
        ((sec=num%60))
        ((num=num/60))
        if((num>59));then
            ((min=num%60))
            ((num=num/60))
            if((num>23));then
                ((hour=num%24))
                ((day=num/24))
            else
                ((hour=num))
            fi
        else
            ((min=num))
        fi
    else
        ((sec=num))
    fi
    echo "$day"d "$hour"h "$min"m "$sec"s
}

#decides what command to run, if any, to create timelapse
function create_timelapse () {
    printf "[-] Beginning timelapse creation.\n"
while [[ -z $createJob ]]; do
    if [[ ${speed} = "0" ]];
        then
            printf "[OK] No Timelapse created due to user input.\n"
            mv $preparedTransportStreamIn ./$dirTime/
    elif [[ ! -z ${compressionFactor} && ! -z ${preset} && ! -z ${speed} ]]; then
            printf "[-] Option 1 Selected with CRF=$compressionFactor and Preset=$preset and Frame Rate=$frameRate\n"
            ffmpeg -i $preparedTransportStreamIn -c:v libx264 -preset $preset -filter:v "setpts=$frameRate*PTS" -crf $compressionFactor $finalProduct 2>>./$dirTime/tmp/mux.log
            createJob=done
    elif [[ -z ${compressionFactor} && ! -z ${preset} && ! -z ${speed} ]]; then
            printf "[-] Option 2 Selected with no CRF and Preset=$preset and Frame Rate=$frameRate\n"
            ffmpeg -i $preparedTransportStreamIn -c:v libx264 -preset $preset -filter:v "setpts=$frameRate*PTS" $finalProduct 2>>./$dirTime/tmp/mux.log
            createJob=done
    elif [[ ! -z ${compressionFactor} && -z ${preset} && ! -z ${speed} ]]; then
            printf "[-] Option 3 Selected with CRF=$compressionFactor and no Preset and Frame Rate=$frameRate\n"
            ffmpeg -i $preparedTransportStreamIn -c:v libx264 -filter:v "setpts=$frameRate*PTS" -crf $compressionFactor $finalProduct 2>>./$dirTime/tmp/mux.log
            createJob=done
    elif [[ -z ${preset} && -z ${compressionFactor} && ! -z ${speed} ]]; then
            printf "[-] Option 4 Selected with no CRF and no Preset and Frame Rate=$frameRate\n"
            ffmpeg -i $preparedTransportStreamIn -c:v libx264 -filter:v "setpts=$frameRate*PTS" $finalProduct 2>>./$dirTime/tmp/mux.log
            createJob=done
    else 
            createJob=fail
            printf "\n[!] Not sure how you managed that. You're likely boned.\n"
    fi
done
if [[ ${createJob} = done ]]; then
    printf "[OK] Timelapse created (or skipped).\n"
fi
}

#generate post report
function generate_report () {
    touch ./$dirTime/final/report.txt
    printf "Time Taken to Prepare:\n" >> ./$dirTime/final/report.txt
    show_time $prepRunTime >> ./$dirTime/final/report.txt
    printf "\nTime Taken to Complete Timelapse:\n" >> ./$dirTime/final/report.txt
    show_time $timelapseRunTime >> ./$dirTime/final/report.txt
    printf "\nSettings Used:\n" >> ./$dirTime/final/report.txt
    printf "ffmpeg preset: %s\n" "$preset" >> ./$dirTime/final/report.txt
    printf "CRF: %s\n" "$compressionFactor" >> ./$dirTime/final/report.txt
    printf "Speed: %s\nx" "$speed" >> ./$dirTime/final/report.txt
    printf "\nFiles Created:\n" >> ./$dirTime/final/report.txt
    printf  "$(du -h ./$dirTime/final/*)" >> ./$dirTime/final/report.txt
}

#cleanup
function cleanup () {
    printf "[-] Beginning cleanup tasks.\n"
    mv ./$dirTime/tmp/*.log ./$dirTime/
    mv ./$dirTime/final/* ./$dirTime/
    rm -r ./$dirTime/tmp
    rm -r ./$dirTime/final
    printf "[OK] Cleanup tasks complete.\n"
}

#The Meat and Potatoes

get_opts "$@"

main

#if you've read this far, you're sick.
