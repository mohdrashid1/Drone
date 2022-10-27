#!/bin/bash
# Begin
# Script Purpose: This script does following things:
#                 1. Will update/regenerate playbooks of a project if --playbookRegenerate flag is set as true.
#
#                 2. Will trigger a scan on a project.
#
#                 3. Will generate Sarif file after scan trigger gets completed, if --outputfile parameter passed as "sarif".
#                    We can use it to  file Vulnerabilities in Github CodeScanning/SecurityCenter.
#
#                 4. Checks vulnerability count of a severity like "Critical" and breaks pipeline execution if threshold limit is breached.
#                    Only when User need to set flag --vulnerabilityPolicy as true to trigger severity check otherwise it won't trigger.
#
#                    i) If user only set flag --vulnerabilityPolicy as true and didn't pass any severity then default use case will be checked.
#                       In the default use-case Critical and High severity will be checked and script willbreak pipeline execution even if any 
#                       one vulnerability is found for either of them as threshold for all the use-cases is zero if user didn't pass threshold value.
#
#                    ii) If user set flag --vulnerabilityPolicy as true and severity as Critical, then only Critical severity will checked.
#
#                    iii) If user set flag --vulnerabilityPolicy as true and severity as High, then Critical and High severity will checked.
#
#                     iv) If user set flag --vulnerabilityPolicy as true and severity as Medium, then Critical, High and Medium severity will checked.
#
#                         We need to pass --severity "<severity>" --threshold <integer no.> flags.
#
#                 5. To get email reports for trigger scans we need to set --emailReport flag as "true".
#
#
# How to run the this script.
# Synxtax:       bash apisec-scan-trigger.sh --hostname "<Hostname or IP>"        --username "<username>"       --password "<password>"   --projectname "<projectname>" --profile "<profile_name>" --scanner "<Scanner_Name>" --emailReport <true/false>   --reportType <report type to be email>  --outputfile "<outputfile-name>"  --severity "<severity>" --threshold <integer no.>   --playbookRegenerate <true/false>   --vulnerabilityPolicy <true/false>

# Example usage: bash apisec-scan-trigger.sh --hostname "https://cloud.apisec.ai"  --username "admin@apisec.ai" --password "apisec@5421"   --projectname "devops"       --profile "Master"         --scanner "Super_1"        --emailReport true           --reportType "RUN_SUMMARY"              --outputfile "sarif"              --severity "High"       --threshold 3               --playbookRegenerate true           --vulnerabilityPolicy true                


TEMP=$(getopt -n "$0" -a -l "hostname:,username:,password:,projectname:,profile:,scanner:,emailReport:,reportType:,tags:,outputfile:,severity:,threshold:,playbookRegenerate:,vulnerabilityPolicy:" -- -- "$@")

    [ $? -eq 0 ] || exit

    eval set --  "$TEMP"

    while [ $# -gt 0 ]
    do
             case "$1" in
		    --hostname) FX_HOST="$2"; shift;;
                    --username) FX_USER="$2"; shift;;
                    --password) FX_PWD="$2"; shift;;
                    --projectname) FX_PROJECT_NAME="$2"; shift;;
                    --profile) JOB_NAME="$2"; shift;;
                    --scanner) REGION="$2"; shift;;
                    --emailReport) FX_EMAIL_REPORT="$2"; shift;;
                    --severity) SEVERITY="$2"; shift;;
                    --threshold) THRESHOLD="$2"; shift;;
                    --playbookRegenerate) PLAYBOOK_REGENERATE="$2"; shift;;
                    --vulnerabilityPolicy) VULNERABILITY_POLCY="$2"; shift;;
                    --reportType) FX_REPORT_TYPE="$2"; shift;;
                    --tags) FX_TAGS="$2"; shift;;
                    --outputfile) OUTPUT_FILENAME="$2"; shift;;
                    --) shift;;
             esac
             shift;
    done



#USER=$1
#PWD=$2
#PROJECT=$3
#JOB=$4
#REGION=$5
#OUTPUT_FILENAME=$6
#SEVERITY=$7
#THRESHOLD=$8
#PLAYBOOK_REGENERATE=$9
#FX_EMAIL_REPORT=${10}

if [ "$FX_HOST" = "" ];
then
FX_HOST="https://cloud.apisec.ai"
fi


FX_SCRIPT=""
if [ "$FX_TAGS" != "" ];
then
FX_SCRIPT="&tags=script:"+${FX_TAGS}
fi

PARAM_SCRIPT=""
if [ "$JOB" != "" ];
then
PARAM_SCRIPT="?jobName="${JOB}
  if [ "$REGION" != "" ];
  then
  PARAM_SCRIPT=${PARAM_SCRIPT}"&region="${REGION}
  fi
elif [ "$REGION" != "" ];
  then
  PARAM_SCRIPT="?region="${REGION}
fi

if   [ "$FX_EMAIL_REPORT" == ""  ]; then
        FX_EMAIL_REPORT=false
fi

if   [ "$PLAYBOOK_REGENERATE" == ""  ]; then
        PLAYBOOK_REGENERATE=false
fi


if [ "$SEVERITY" == "Critical" ] && [ "$THRESHOLD" == "" ]; then
        THRESHOLD=0
fi


if [ "$SEVERITY" == "High" ] && [ "$THRESHOLD" == "" ]; then
      THRESHOLD=0
fi


if [ "$SEVERITY" == "Medium" ] && [ "$THRESHOLD" == "" ]; then
      THRESHOLD=0
fi

if [ "$SEVERITY" == "" ] && [ "$THRESHOLD" == "" ]; then
      THRESHOLD=0
fi

token=$(curl -s -H "Content-Type: application/json" -X POST -d '{"username": "'${FX_USER}'", "password": "'${FX_PWD}'"}' "${FX_HOST}/login" | jq -r .token)

echo "generated token is:" $token
echo " "
echo "The request is ${FX_HOST}/api/v1/runs/projectName/${FX_PROJECT_NAME}${PARAM_SCRIPT}"
echo " "


if [ "$PLAYBOOK_REGENERATE" = true ]; then

      dto=$(curl -s --location --request GET  "${FX_HOST}/api/v1/projects/find-by-name/${FX_PROJECT_NAME}" --header "Accept: application/json" --header "Content-Type: application/json" --header "Authorization: Bearer "$token"" | jq -r '.data')
projectId=$(echo "$dto" | jq -r '.id')

     curl -s -X PUT "${FX_HOST}/api/v1/projects/${projectId}/refresh-specs" -H "accept: */*" -H "Content-Type: application/json" --header "Authorization: Bearer "$token"" -d "$dto" > /dev/null
     
     playbookTaskStatus="In_progress"
     echo "playbookTaskStatus = " $playbookTaskStatus
     retryCount=0
     pCount=0

     while [ "$playbookTaskStatus" == "In_progress" ]
            do
                 if [ $pCount -eq 0 ]; then
                      echo "Checking playbooks regenerate task Status...."
                 fi
                 pCount=`expr $pCount + 1`  
                 retryCount=`expr $retryCount + 1`  
                 sleep 2

                 playbookTaskStatus=$(curl -s -X GET "${FX_HOST}/api/v1/events/project/${projectId}/Sync" -H "accept: */*" -H "Content-Type: application/json" --header "Authorization: Bearer "$token"" | jq -r '."data".status')
                 #playbookTaskStatus="In_progress"
                 if [ "$playbookTaskStatus" == "Done" ]; then
                      echo "Playbooks regenerate task is succesfully completed!!!"
                 fi

                 if [ $retryCount -ge 55  ]; then
                      echo " "
                      retryCount=`expr $retryCount \* 2`  
                      echo "Playbook Regenerate Task Status $playbookTaskStatus even after $retryCount seconds, so halting script execution!!!"
                      exit 1
                 fi                            
            done
  
fi

sCount=0
echo " "

data=$(curl -s --location --request POST "${FX_HOST}/api/v1/runs/project/${FX_PROJECT_NAME}?jobName=${JOB}&region=${REGION}&emailReport=${FX_EMAIL_REPORT}&reportType=RUN_SUMMARY${FX_SCRIPT}" --header "Authorization: Bearer "$token"" | jq '.data')

runId=$( jq -r '.id' <<< "$data")
projectId=$( jq -r '.job.project.id' <<< "$data")
echo "runId =" $runId

if [  -z "$runId" ]
then
     echo "RunId = " "$runId"
     echo "Invalid runid"
     echo $(curl -s --location --request POST "${FX_HOST}/api/v1/runs/projectName/${FX_PROJECT_NAME}${PARAM_SCRIPT}" --header "Authorization: Bearer "$token"" | jq -r '.["data"]|.id')
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

          sCount=`expr $sCount + 1`
          if [ "$taskStatus" == "COMPLETED" ];then
              echo "------------------------------------------------"
              # echo  "Run detail link https://cloud.apisec.ai/${array[7]}"
              echo  "Run detail link ${FX_HOST}/${array[7]}"
              echo "-----------------------------------------------"
              echo "Scan Successfully Completed!!!"
              if [ "$OUTPUT_FILENAME" != "" ];
              then
                     sarifoutput=$(curl -s --location --request GET "${FX_HOST}/api/v1/projects/${projectId}/sarif" --header "Authorization: Bearer "$token"" | jq  '.data')
		     echo $sarifoutput >> $OUTPUT_FILENAME
		     echo "SARIF output file created successfully"
                     echo " "
              fi

              if [ "$VULNERABILITY_POLCY" = true ]; then


                     case "$SEVERITY" in
                         "Critical") vulCount=$(curl -s -X GET "${FX_HOST}/api/v1/projects/${projectId}/vulnerabilities?&severity=${SEVERITY}&page=0&pageSize=20" -H "accept: */*"  "Content-Type: application/json" --header "Authorization: Bearer "$token"" | jq -r '.totalElements')
                                     if [ $vulCount -gt $THRESHOLD ]; then
                                          echo "Failing script execution since we have found $vulCount "$SEVERITY" severity vulnerabilities which are greater than threshold limit of $THRESHOLD"
                                           exit 1
                                     fi
                         ;;
                        "High") severity=$(curl -s -X GET "${FX_HOST}/api/v1/projects/${projectId}/vulnerabilities?&severity=${SEVERITY},Critical&page=0&pageSize=20" -H "accept: */*"  "Content-Type: application/json" --header "Authorization: Bearer "$token"" | jq -r '.data[] | .severity')
                                vulCount=$(curl -s -X GET "${FX_HOST}/api/v1/projects/${projectId}/vulnerabilities?&severity=${SEVERITY},Critical&page=0&pageSize=20" -H "accept: */*"  "Content-Type: application/json" --header "Authorization: Bearer "$token"" | jq -r '.totalElements')     
                                cVulCount=0
                                for cVul in ${severity}
                                    do
                                         if  [ "$cVul" == "Critical"  ]; then                                        
                                                cVulCount=`expr $cVulCount + 1`                                                
                                         fi
                                    done

                                hVulCount=0
                                for hVul in ${severity}
                                    do
                                         if  [ "$hVul" == "High"  ]; then                                        
                                                hVulCount=`expr $hVulCount + 1`                                                
                                         fi
                                    done
                                combinedVulCount=`expr $cVulCount + $hVulCount`
                                if [ $vulCount -gt $THRESHOLD ]; then
                                     echo "Failing script execution since we have found $cVulCount Critical and $hVulCount High severity, in total $combinedVulCount  vulnerabilities which are greater than threshold limit of $THRESHOLD"
                                     exit 1
                                fi
                         ;;
                        "Medium") severity=$(curl -s -X GET "${FX_HOST}/api/v1/projects/${projectId}/vulnerabilities?&severity=${SEVERITY},High,Critical&page=0&pageSize=20" -H "accept: */*"  "Content-Type: application/json" --header "Authorization: Bearer "$token"" | jq -r '.data[] | .severity')
                                  vulCount=$(curl -s -X GET "${FX_HOST}/api/v1/projects/${projectId}/vulnerabilities?&severity=${SEVERITY},High,Critical&page=0&pageSize=20" -H "accept: */*"  "Content-Type: application/json" --header "Authorization: Bearer "$token"" | jq -r '.totalElements')     
                                  cVulCount=0
                                  for cVul in ${severity}
                                      do
                                          if  [ "$cVul" == "Critical"  ]; then                                        
                                                 cVulCount=`expr $cVulCount + 1`                                                
                                          fi
                                      done

                                  hVulCount=0
                                  for hVul in ${severity}
                                      do
                                          if  [ "$hVul" == "High"  ]; then                                        
                                                 hVulCount=`expr $hVulCount + 1`                                                
                                          fi
                                      done
                                  mVulCount=0
                                  for mVul in ${severity}
                                      do
                                          if  [ "$mVul" == "Medium"  ]; then                                        
                                                 mVulCount=`expr $mVulCount + 1`                                                
                                          fi
                                      done
                                  combinedVulCount=`expr $cVulCount + $hVulCount + $mVulCount`
                                  if [ $vulCount -gt $THRESHOLD ]; then
                                        echo "Failing script execution since we have found $cVulCount Critical,  $hVulCount High and $mVulCount Medium severity in total $combinedVulCount  vulnerabilities which are greater than threshold limit of $THRESHOLD"
                                        exit 1
                                  fi
                        ;;
                      *)
                          
                                severity=$(curl -s -X GET "${FX_HOST}/api/v1/projects/${projectId}/vulnerabilities?&severity=High,Critical&page=0&pageSize=20" -H "accept: */*"  "Content-Type: application/json" --header "Authorization: Bearer "$token"" | jq -r '.data[] | .severity')
                                vulCount=$(curl -s -X GET "${FX_HOST}/api/v1/projects/${projectId}/vulnerabilities?&severity=High,Critical&page=0&pageSize=20" -H "accept: */*"  "Content-Type: application/json" --header "Authorization: Bearer "$token"" | jq -r '.totalElements')     
                                cVulCount=0
                                for cVul in ${severity}
                                    do
                                         if  [ "$cVul" == "Critical"  ]; then                                        
                                                cVulCount=`expr $cVulCount + 1`                                                
                                         fi
                                    done

                                hVulCount=0
                                for hVul in ${severity}
                                    do
                                         if  [ "$hVul" == "High"  ]; then                                        
                                                hVulCount=`expr $hVulCount + 1`                                                
                                         fi
                                    done
                                combinedVulCount=`expr $cVulCount + $hVulCount`
                                if [ $vulCount -gt $THRESHOLD ]; then
                                     echo "Failing script execution since we have found $cVulCount Critical and $hVulCount High severity, in total $combinedVulCount  vulnerabilities which are greater than threshold limit of $THRESHOLD"
                                     exit 1
                                fi   
                     esac
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
return 0


















































































































































# TEMP=$(getopt -n "$0" -a -l "hostname:,username:,password:,projectname:,profile:,scanner:,emailReport:,reportType:,tags:,outputfile:,severity:,threshold:,playbookRegenerate:," -- -- "$@")

#     [ $? -eq 0 ] || exit

#     eval set --  "$TEMP"

#     while [ $# -gt 0 ]
#     do
#              case "$1" in
# 		    --hostname) FX_HOST="$2"; shift;;
#                     --username) FX_USER="$2"; shift;;
#                     --password) FX_PWD="$2"; shift;;
#                     --projectname) FX_PROJECT_NAME="$2"; shift;;
#                     --profile) JOB_NAME="$2"; shift;;
#                     --scanner) REGION="$2"; shift;;
#                     --emailReport) FX_EMAIL_REPORT="$2"; shift;;
#                     --severity) SEVERITY="$2"; shift;;
#                     --threshold) THRESHOLD="$2"; shift;;
#                     --playbookRegenerate) PLAYBOOK_REGENERATE="$2"; shift;;
#                     --reportType) FX_REPORT_TYPE="$2"; shift;;
#                     --tags) FX_TAGS="$2"; shift;;
#                     --outputfile) OUTPUT_FILENAME="$2"; shift;;
#                     --) shift;;
#              esac
#              shift;
#     done



# #USER=$1
# #PWD=$2
# #PROJECT=$3
# #JOB=$4
# #REGION=$5
# #OUTPUT_FILENAME=$6
# #SEVERITY=$7
# #THRESHOLD=$8
# #PLAYBOOK_REGENERATE=$9
# #FX_EMAIL_REPORT=${10}

# if [ "$FX_HOST" = "" ];
# then
# FX_HOST="https://cloud.apisec.ai"
# fi


# FX_SCRIPT=""
# if [ "$FX_TAGS" != "" ];
# then
# FX_SCRIPT="&tags=script:"+${FX_TAGS}
# fi

# PARAM_SCRIPT=""
# if [ "$JOB" != "" ];
# then
# PARAM_SCRIPT="?jobName="${JOB}
#   if [ "$REGION" != "" ];
#   then
#   PARAM_SCRIPT=${PARAM_SCRIPT}"&region="${REGION}
#   fi
# elif [ "$REGION" != "" ];
#   then
#   PARAM_SCRIPT="?region="${REGION}
# fi

# if   [ "$FX_EMAIL_REPORT" == ""  ]; then
#         FX_EMAIL_REPORT=false
# fi

# if   [ "$PLAYBOOK_REGENERATE" == ""  ]; then
#         PLAYBOOK_REGENERATE=false
# fi


# if [ "$SEVERITY" == "Critical" ] && [ "$THRESHOLD" == "" ]; then
#         THRESHOLD=0
# fi


# if [ "$SEVERITY" == "High" ] && [ "$THRESHOLD" == "" ]; then
#       THRESHOLD=3
# fi


# if [ "$SEVERITY" == "Medium" ] && [ "$THRESHOLD" == "" ]; then
#       THRESHOLD=5
# fi


# token=$(curl -s -H "Content-Type: application/json" -X POST -d '{"username": "'${FX_USER}'", "password": "'${FX_PWD}'"}' "${FX_HOST}/login" | jq -r .token)

# echo "generated token is:" $token
# echo " "
# echo "The request is ${FX_HOST}/api/v1/runs/projectName/${FX_PROJECT_NAME}${PARAM_SCRIPT}"
# echo " "


# if [ "$PLAYBOOK_REGENERATE" = true ]; then

#       dto=$(curl -s --location --request GET  "${FX_HOST}/api/v1/projects/find-by-name/${FX_PROJECT_NAME}" --header "Accept: application/json" --header "Content-Type: application/json" --header "Authorization: Bearer "$token"" | jq -r '.data')
# projectId=$(echo "$dto" | jq -r '.id')

#      curl -s -X PUT "${FX_HOST}/api/v1/projects/${projectId}/refresh-specs" -H "accept: */*" -H "Content-Type: application/json" --header "Authorization: Bearer "$token"" -d "$dto" > /dev/null
     
#      playbookTaskStatus="In_progress"
#      echo "playbookTaskStatus = " $playbookTaskStatus
#      retryCount=0
#      pCount=0

#      while [ "$playbookTaskStatus" == "In_progress" ]
#             do
#                  if [ $pCount -eq 0 ]; then
#                       echo "Checking playbooks regenerate task Status...."
#                  fi
#                  pCount=`expr $pCount + 1`  
#                  retryCount=`expr $retryCount + 1`  
#                  sleep 2

#                  playbookTaskStatus=$(curl -s -X GET "${FX_HOST}/api/v1/events/project/${projectId}/Sync" -H "accept: */*" -H "Content-Type: application/json" --header "Authorization: Bearer "$token"" | jq -r '."data".status')
#                  #playbookTaskStatus="In_progress"
#                  if [ "$playbookTaskStatus" == "Done" ]; then
#                       echo "Playbooks regenerate task is succesfully completed!!!"
#                  fi

#                  if [ $retryCount -ge 55  ]; then
#                       echo " "
#                       retryCount=`expr $retryCount \* 2`  
#                       echo "Playbook Regenerate Task Status $playbookTaskStatus even after $retryCount seconds, so halting script execution!!!"
#                       exit 1
#                  fi                            
#             done
  
# fi

# sCount=0
# echo " "

# data=$(curl -s --location --request POST "${FX_HOST}/api/v1/runs/project/${FX_PROJECT_NAME}?jobName=${JOB}&region=${REGION}&emailReport=${FX_EMAIL_REPORT}&reportType=RUN_SUMMARY${FX_SCRIPT}" --header "Authorization: Bearer "$token"" | jq '.data')


# runId=$( jq -r '.id' <<< "$data")
# projectId=$( jq -r '.job.project.id' <<< "$data")

# echo "runId =" $runId

# if [  -z "$runId" ]
# then
#      echo "RunId = " "$runId"
#      echo "Invalid runid"
#      echo $(curl -s --location --request POST "${FX_HOST}/api/v1/runs/projectName/${FX_PROJECT_NAME}${PARAM_SCRIPT}" --header "Authorization: Bearer "$token"" | jq -r '.["data"]|.id')
#      exit 1
# fi

# taskStatus="WAITING"
# echo "taskStatus = " $taskStatus

# while [ "$taskStatus" == "WAITING" -o "$taskStatus" == "PROCESSING" ]
#       do
#           sleep 5
#           if [ $sCount -eq 0 ]; then
#                echo "Checking Trigger Scan Status...."
#                sleep 15
#           fi

#           passPercent=$(curl -s --location --request GET "${FX_HOST}/api/v1/runs/${runId}" --header "Authorization: Bearer "$token""| jq -r '.["data"]|.ciCdStatus')
 
#           IFS=':' read -r -a array <<< "$passPercent"

#           taskStatus="${array[0]}"
#           if [ $sCount -eq 0 ] || [ "$taskStatus" == "COMPLETED" ]; then 
#                echo "Status =" "${array[0]}" " Success Percent =" "${array[1]}"  " Total Tests =" "${array[2]}" " Total Failed =" "${array[3]}" " Run =" "${array[6]}"
#           echo " "
#           fi   

#           sCount=`expr $sCount + 1`
#           if [ "$taskStatus" == "COMPLETED" ];then
#               echo "------------------------------------------------"
#               # echo  "Run detail link ${FX_HOST}/${array[7]}"
#               echo  "Run detail link ${FX_HOST}/${array[7]}"
#               echo "-----------------------------------------------"
#               echo "Scan Successfully Completed!!!"
#               if [ "$OUTPUT_FILENAME" != "" ];
#               then
#                      sarifoutput=$(curl -s --location --request GET "${FX_HOST}/api/v1/projects/${projectId}/sarif" --header "Authorization: Bearer "$token"" | jq  '.data')
# 		     echo $sarifoutput >> $GITHUB_WORKSPACE/$OUTPUT_FILENAME
# 		     echo "SARIF output file created successfully"
#                      echo " "

#                      if [ "$SEVERITY" == "Critical" ]; then
#                            #severity=$(curl -s -X GET "${FX_HOST}/api/v1/projects/${projectId}/vulnerabilities?&severity=${SEVERITY}&page=0&pageSize=20" -H "accept: */*"  "Content-Type: application/json" --header "Authorization: Bearer "$token"" | jq -r '.data[] | .severity')
#                            vulCount=$(curl -s -X GET "${FX_HOST}/api/v1/projects/${projectId}/vulnerabilities?&severity=${SEVERITY}&page=0&pageSize=20" -H "accept: */*"  "Content-Type: application/json" --header "Authorization: Bearer "$token"" | jq -r '.totalElements')
#                            if [ $vulCount -gt $THRESHOLD ]; then
#                                 echo "Failing script execution since we have found $vulCount "$SEVERITY" severity vulnerabilities which are greater than threshold limit of $THRESHOLD"
#                                 exit 1
#                            fi
#                      fi

#                      if [ "$SEVERITY" == "High" ]; then
#                            severity=$(curl -s -X GET "${FX_HOST}/api/v1/projects/${projectId}/vulnerabilities?&severity=${SEVERITY},Critical&page=0&pageSize=20" -H "accept: */*"  "Content-Type: application/json" --header "Authorization: Bearer "$token"" | jq -r '.data[] | .severity')
#                            vulCount=$(curl -s -X GET "${FX_HOST}/api/v1/projects/${projectId}/vulnerabilities?&severity=${SEVERITY},Critical&page=0&pageSize=20" -H "accept: */*"  "Content-Type: application/json" --header "Authorization: Bearer "$token"" | jq -r '.totalElements')     
#                            cVulCount=0
#                            for cVul in ${severity}
#                                do
#                                    if  [ "$cVul" == "Critical"  ]; then                                        
#                                           cVulCount=`expr $cVulCount + 1`                                                
#                                    fi
#                                done

#                            hVulCount=0
#                            for hVul in ${severity}
#                                do
#                                    if  [ "$hVul" == "High"  ]; then                                        
#                                           hVulCount=`expr $hVulCount + 1`                                                
#                                    fi
#                                done

#                            if [ $vulCount -gt $THRESHOLD ]; then
#                                 echo "Failing script execution since we have found $cVulCount Critical and $hVulCount High severity,  in total $vulCount vulnerabilities which are greater than threshold limit of $THRESHOLD"
#                                 exit 1
#                            fi
#                      fi


#                      if [ "$SEVERITY" == "Medium" ]; then
#                            severity=$(curl -s -X GET "${FX_HOST}/api/v1/projects/${projectId}/vulnerabilities?&severity=${SEVERITY},High,Critical&page=0&pageSize=20" -H "accept: */*"  "Content-Type: application/json" --header "Authorization: Bearer "$token"" | jq -r '.data[] | .severity')
#                            vulCount=$(curl -s -X GET "${FX_HOST}/api/v1/projects/${projectId}/vulnerabilities?&severity=${SEVERITY},High,Critical&page=0&pageSize=20" -H "accept: */*"  "Content-Type: application/json" --header "Authorization: Bearer "$token"" | jq -r '.totalElements')     
#                            cVulCount=0
#                            for cVul in ${severity}
#                                do
#                                    if  [ "$cVul" == "Critical"  ]; then                                        
#                                           cVulCount=`expr $cVulCount + 1`                                                
#                                    fi
#                                done

#                            hVulCount=0
#                            for hVul in ${severity}
#                                do
#                                    if  [ "$hVul" == "High"  ]; then                                        
#                                           hVulCount=`expr $hVulCount + 1`                                                
#                                    fi
#                                done
#                            mVulCount=0
#                            for mVul in ${severity}
#                                do
#                                    if  [ "$mVul" == "Medium"  ]; then                                        
#                                           mVulCount=`expr $mVulCount + 1`                                                
#                                    fi
#                                done

#                            if [ $vulCount -gt $THRESHOLD ]; then
#                                 echo "Failing script execution since we have found $cVulCount Critical,  $hVulCount High and $mVulCount Medium severity, in total $vulCount vulnerabilities which are greater than threshold limit of $THRESHOLD"
#                                 exit 1
#                            fi
#                      fi


#               fi                                             
#               exit 0
#           fi
#       done

# if [ "$taskStatus" == "TIMEOUT" ];then
#       echo "Task Status = " $taskStatus
#       exit 1
# fi

# echo "$(curl -s --location --request GET "${FX_HOST}/api/v1/runs/${runId}" --header "Authorization: Bearer "$token"")"
# exit 1
# return 0

