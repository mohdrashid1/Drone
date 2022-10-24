#!/bin/bash
# Begin
# Script Purpose: This script will update/rgenerate playbooks of a project and upon successful operation will trigger a scan.
#
# How to run the this script.
# Synxtax:       bash apisec_playbooks_regenerate_scan_trigger.sh --host "<Hostname or IP>" --username "<username>" --password "<password>"   --projectname "<projectname>" --profile "<profile_name>" --scanner "<Scanner_Name>" --emailReport <true/false> --reportType <report type to be email> --outputfile "<>"

# Example usage: bash apisec_playbooks_regenerate_scan_trigger.sh --host "https://cloud.apisec.ai"  --username "admin@apisec.ai" --password "apisec@5421" --projectname "devops" --profile "Master" --scanner "Super_1" --emailReport true --reportType "RUN_SUMMARY" --outputfile "sarif"


TEMP=$(getopt -n "$0" -a -l "host:,username:,password:,projectname:,profile:,scanner:,emailReport:,reportType:,tags:, outputfile:" -- -- "$@")

    [ $? -eq 0 ] || exit

    eval set --  "$TEMP"

    while [ $# -gt 0 ]
    do
             case "$1" in
		    --host) FX_HOST="$2"; shift;;
                    --username) FX_USER="$2"; shift;;
                    --password) FX_PWD="$2"; shift;;
                    --projectname) FX_PROJECT_NAME="$2"; shift;;
                    --profile) JOB_NAME="$2"; shift;;
                    --scanner) REGION="$2"; shift;;
                    --emailReport) FX_EMAIL_REPORT="$2"; shift;;
                    --reportType) FX_REPORT_TYPE="$2"; shift;;
                    --tags) FX_TAGS="$2"; shift;;
                    --outputfile) OUTPUT_FILENAME="$2"; shift;;
                    --) shift;;
             esac
             shift;
    done
    
#FX_USER=$1
#FX_PWD=$2
#FX_JOBID=$3
#REGION=$4
#FX_ENVID=$5
#FX_PROJECTID=$6
#FX_EMAIL_REPORT=$7
#FX_TAGS=$8

if [ "$FX_HOST" = "" ];
then
FX_HOST="https://cloud.apisec.ai"
fi

FX_SCRIPT=""
if [ "$FX_TAGS" != "" ];
then
FX_SCRIPT="&tags=script:"+${FX_TAGS}
fi

token=$(curl -s -H "Content-Type: application/json" -X POST -d '{"username": "'${FX_USER}'", "password": "'${FX_PWD}'"}' ${FX_HOST}/login | jq -r .token)

echo "generated token is:" $token
echo " "
URL="${FX_HOST}/api/v1/runs/project/${FX_PROJECT_NAME}?jobName=${JOB_NAME}&region=${REGION}&emailReport=${FX_EMAIL_REPORT}&reportType=${FX_REPORT_TYPE}${FX_SCRIPT}"

url=$( echo "$URL" | sed 's/ /%20/g' )

dto=$(curl -s --location --request GET  "${FX_HOST}/api/v1/projects/find-by-name/${FX_PROJECT_NAME}" --header "Accept: application/json" --header "Content-Type: application/json" --header "Authorization: Bearer "$token"" | jq -r '.data')
projectId=$(echo "$dto" | jq -r '.id')

echo "Project Name: ${FX_PROJECT_NAME}"
echo "ProjectID: $projectId"

curl -s -X PUT "${FX_HOST}/api/v1/projects/${projectId}/refresh-specs" -H "accept: */*" -H "Content-Type: application/json" --header "Authorization: Bearer "$token"" -d "$dto" > /dev/null

playbookTaskStatus="In_progress"
echo "playbookTaskStatus = " $playbookTaskStatus
retryCount=0
pCount=0
sCount=0

while [ "$playbookTaskStatus" == "In_progress" ]
         do
                if [ $pCount -eq 0 ]; then
                     echo "Checking playbooks regenerate task Status...."
                fi
                pCount=`expr $pCount + 1`  
                retryCount=`expr $retryCount + 1`  
                sleep 2

                playbookTaskStatus=$(curl -s -X GET "https://developer.apisec.ai/api/v1/events/project/${projectId}/Sync" -H "accept: */*" -H "Content-Type: application/json" --header "Authorization: Bearer "$token"" | jq -r '."data".status')
                #playbookTaskStatus="In_progress"

                if [ $retryCount -ge 110  ]; then
                     echo " "
                     echo "Playbook Task Status $playbookTaskStatus even after $retryCount seconds, so halting script execution!!!"
                     exit 1
                fi
                                 


                if [ "$playbookTaskStatus" == "Done" ];then
                   
                   echo "Playbook regenerate task status is: $playbookTaskStatus so triggering a scan!!!"
                   echo " "
                   runId=$(curl -s --location --request POST "$url" --header "Authorization: Bearer "$token"" | jq -r '.["data"]|.id')
                   echo "runId =" $runId

                   if [ -z "$runId" ]
                   then
                             echo "RunId = " "$runId"
                             echo "Invalid runid"
                             echo $(curl -s --location --request POST "${FX_HOST}/api/v1/runs/project/${FX_PROJECT_NAME}?jobName=${JOB_NAME}&region=${REGION}&emailReport=${FX_EMAIL_REPORT}&reportType=${FX_REPORT_TYPE}${FX_SCRIPT}" --header "Authorization: Bearer "$token"" | jq -r '.["data"]|.id')
                             exit 1
                   fi

                   taskStatus="WAITING"
                   echo "taskStatus = " $taskStatus

                   while [ "$taskStatus" == "WAITING" -o "$taskStatus" == "PROCESSING" ]
                            do
                                 sleep 5
                                 if [ $sCount -eq 0 ]; then
                                    echo "Checking Trigger Scan Status...."
                                    sleep 15
                                 fi

                                 passPercent=$(curl -s --location --request GET "${FX_HOST}/api/v1/runs/${runId}" --header "Authorization: Bearer "$token""| jq -r '.["data"]|.ciCdStatus')
 
                                         IFS=':' read -r -a array <<< "$passPercent"

                                         taskStatus="${array[0]}"
                                         if [ $sCount -eq 0 ] || [ "$taskStatus" == "COMPLETED" ]; then 
                                            echo "Status =" "${array[0]}" " Success Percent =" "${array[1]}"  " Total Tests =" "${array[2]}" " Total Failed =" "${array[3]}" " Run =" "${array[6]}"
                                            echo " "
                                         fi
                                       # VAR2=$(echo "Status =" "${array[0]}" " Success Percent =" "${array[1]}"  " Total Tests =" "${array[2]}" " Total Failed =" "${array[3]}" " Run =" "${array[6]}")      

                                 sCount=`expr $sCount + 1`
                                 if [ "$taskStatus" == "COMPLETED" ];then
                                   echo "------------------------------------------------"
                                   # echo  "Run detail link ${FX_HOST}/${array[7]}"
                                   echo  "Run detail link ${FX_HOST}${array[7]}"
                                   echo "-----------------------------------------------"
                                   echo "Scan Successfully Completed!!!"
                                   if [ "$OUTPUT_FILENAME" != "" ];
                                   then
                                         sarifoutput=$(curl -s --location --request GET "${FX_HOST}/api/v1/projects/${projectId}/sarif" --header "Authorization: Bearer "$token"" | jq  '.data')
			                 echo $sarifoutput >> $OUTPUT_FILENAME
					 echo "SARIF output file created successfully"
                                         echo " "
                                         severity=$(curl -s -X GET "${FX_HOST}/api/v1/projects/${projectId}/vulnerabilities?&severity=All&page=0&pageSize=20" -H "accept: */*"  "Content-Type: application/json" --header "Authorization: Bearer "$token"" | jq -r '.data[] | .severity')

                                         tCount=0
                                         for vul in ${severity}
                                             do
                                                
                                                tCount=`expr $tCount + 1`
                                             done
                                         echo "Total Vulnerabilities found are: $tCount"
                                         if [ $tCount -gt 12 ]; then
                                               echo "Failing script execution since Total Vulnerabilities found are: $tCount which are greater than thrshold value of 12 vulnerablities"
                                               exit 1
                                         fi

                                         vCount=1
                                         for vul in ${severity}
                                             do
                                                
                                                if [ "$vul" == "High"  ] || [ "$vul" == "Critical"  ]; then
                                                         echo "Count: $vCount Failing script execution since we found "$vul" vulnerability!!!"
                                                         exit 1
                                             
                                                fi
                                                vCount=`expr $vCount + 1`
                                             done

                                   fi
                                   exit 0

                                 fi
                            done

                   if [ "$taskStatus" == "TIMEOUT" ];then
                          echo "Task Status = " $taskStatus
                          exit 1
                   fi

                   echo "$(curl -s --location --request GET "${FX_HOST}/api/v1/runs/${runId}" --header "Authorization: Bearer "$token"")"
                   exit 1
                fi

         done
return 0


