#!/bin/bash
# Begin
USER=$1
PWD=$2
PROJECT=$3
JOB=$4
REGION=$5
OUTPUT_FILENAME=$6
SEVERITY=$7
THRESHOLD=$8
PLAYBOOK_REGENERATE=$9
FX_EMAIL_REPORT=${10}
#THRESHOLD="${THRESHOLD:-0}"

#echo "Threshold value: $THRESHOLD"

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
      THRESHOLD=3
fi


if [ "$SEVERITY" == "Medium" ] && [ "$THRESHOLD" == "" ]; then
      THRESHOLD=5
fi


token=$(curl -s -H "Content-Type: application/json" -X POST -d '{"username": "'${USER}'", "password": "'${PWD}'"}' https://cloud.apisec.ai/login | jq -r .token)

echo "generated token is:" $token
echo " "
echo "The request is https://cloud.apisec.ai/api/v1/runs/projectName/${PROJECT}${PARAM_SCRIPT}"
echo " "

if [ "$PLAYBOOK_REGENERATE" = true ]; then

      dto=$(curl -s --location --request GET  "https://cloud.apisec.ai/api/v1/projects/find-by-name/${PROJECT}" --header "Accept: application/json" --header "Content-Type: application/json" --header "Authorization: Bearer "$token"" | jq -r '.data')
projectId=$(echo "$dto" | jq -r '.id')

     curl -s -X PUT "https://cloud.apisec.ai/api/v1/projects/${projectId}/refresh-specs" -H "accept: */*" -H "Content-Type: application/json" --header "Authorization: Bearer "$token"" -d "$dto" > /dev/null
     
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

                 playbookTaskStatus=$(curl -s -X GET "https://cloud.apisec.ai/api/v1/events/project/${projectId}/Sync" -H "accept: */*" -H "Content-Type: application/json" --header "Authorization: Bearer "$token"" | jq -r '."data".status')
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

url="https://cloud.apisec.ai/api/v1/runs/project/${PROJECT}?jobName=${JOB}&region=${REGION}&emailReport=${FX_EMAIL_REPORT}&reportType=RUN_SUMMARY${FX_SCRIPT}"

echo "The runID url is: $url"

data=$(curl -s --location --request POST "$url" --header "Authorization: Bearer "$token"" | jq '.data')

#data=$(curl -s --location --request POST "https://cloud.apisec.ai/api/v1/runs/project/${PROJECT}?jobName=${JOB}&region=${REGION}&emailReport=${FX_EMAIL_REPORT}&reportType=RUN_SUMMARY${FX_SCRIPT}" --header "Authorization: Bearer "$token"" | jq '.data')

#"https://cloud.apisec.ai/api/v1/runs/project/${FX_PROJECT_NAME}?jobName=${JOB_NAME}&region=${REGION}&emailReport=true&reportType=Run_Summary${FX_SCRIPT}"

runId=$( jq -r '.id' <<< "$data")
projectId=$( jq -r '.job.project.id' <<< "$data")

#runId=$(curl -s --location --request POST "https://cloud.apisec.ai/api/v1/runs/projectName/${PROJECT}${PARAM_SCRIPT}"  --header "Authorization: Bearer "$token"" | jq -r '.["data"]|.id')
echo "runId =" $runId

if [ -z "$runId" ]
then
     echo "RunId = " "$runId"
     echo "Invalid runid"
     echo $(curl -s --location --request POST "https://cloud.apisec.ai/api/v1/runs/projectName/${PROJECT}${PARAM_SCRIPT}" --header "Authorization: Bearer "$token"" | jq -r '.["data"]|.id')
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

          passPercent=$(curl -s --location --request GET "https://cloud.apisec.ai/api/v1/runs/${runId}" --header "Authorization: Bearer "$token""| jq -r '.["data"]|.ciCdStatus')
 
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
              echo  "Run detail link https://cloud.apisec.ai/${array[7]}"
              echo "-----------------------------------------------"
              echo "Scan Successfully Completed!!!"
              if [ "$OUTPUT_FILENAME" != "" ];
              then
                     sarifoutput=$(curl -s --location --request GET "https://cloud.apisec.ai/api/v1/projects/${projectId}/sarif" --header "Authorization: Bearer "$token"" | jq  '.data')
		     echo $sarifoutput >> $GITHUB_WORKSPACE/$OUTPUT_FILENAME
		     echo "SARIF output file created successfully"
                     echo " "

                     if [ "$SEVERITY" == "Critical" ]; then
                           #severity=$(curl -s -X GET "https://cloud.apisec.ai/api/v1/projects/${projectId}/vulnerabilities?&severity=${SEVERITY}&page=0&pageSize=20" -H "accept: */*"  "Content-Type: application/json" --header "Authorization: Bearer "$token"" | jq -r '.data[] | .severity')
                           vulCount=$(curl -s -X GET "https://cloud.apisec.ai/api/v1/projects/${projectId}/vulnerabilities?&severity=${SEVERITY}&page=0&pageSize=20" -H "accept: */*"  "Content-Type: application/json" --header "Authorization: Bearer "$token"" | jq -r '.totalElements')
                           if [ $vulCount -gt $THRESHOLD ]; then
                                echo "Failing script execution since we have found $vulCount "$SEVERITY" severity vulnerabilities severity vulnerabilities which are greater than threshold limit of $THRESHOLD"
                                exit 1
                           fi
                     fi

                     if [ "$SEVERITY" == "High" ]; then
                           severity=$(curl -s -X GET "https://cloud.apisec.ai/api/v1/projects/${projectId}/vulnerabilities?&severity=${SEVERITY},Critical&page=0&pageSize=20" -H "accept: */*"  "Content-Type: application/json" --header "Authorization: Bearer "$token"" | jq -r '.data[] | .severity')
                           vulCount=$(curl -s -X GET "https://cloud.apisec.ai/api/v1/projects/${projectId}/vulnerabilities?&severity=${SEVERITY},Critical&page=0&pageSize=20" -H "accept: */*"  "Content-Type: application/json" --header "Authorization: Bearer "$token"" | jq -r '.totalElements')     
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

                           if [ $vulCount -gt $THRESHOLD ]; then
                                echo "Failing script execution since we have found $cVulCount Critical and $hVulCount High severity( inTotal $vulCount)  vulnerabilities which are greater than threshold limit of $THRESHOLD"
                                exit 1
                           fi
                     fi


                     if [ "$SEVERITY" == "Medium" ]; then
                           severity=$(curl -s -X GET "https://cloud.apisec.ai/api/v1/projects/${projectId}/vulnerabilities?&severity=${SEVERITY},High,Critical&page=0&pageSize=20" -H "accept: */*"  "Content-Type: application/json" --header "Authorization: Bearer "$token"" | jq -r '.data[] | .severity')
                           vulCount=$(curl -s -X GET "https://cloud.apisec.ai/api/v1/projects/${projectId}/vulnerabilities?&severity=${SEVERITY},High,Critical&page=0&pageSize=20" -H "accept: */*"  "Content-Type: application/json" --header "Authorization: Bearer "$token"" | jq -r '.totalElements')     
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

                           if [ $vulCount -gt $THRESHOLD ]; then
                                echo "Failing script execution since we have found $cVulCount Critical,  $hVulCount High and $mVulCount Medium severity( inTotal $vulCount)  vulnerabilities which are greater than threshold limit of $THRESHOLD"
                                exit 1
                           fi
                     fi


              fi                                             
              exit 0
          fi
      done

if [ "$taskStatus" == "TIMEOUT" ];then
      echo "Task Status = " $taskStatus
      exit 1
fi

echo "$(curl -s --location --request GET "https://cloud.apisec.ai/api/v1/runs/${runId}" --header "Authorization: Bearer "$token"")"
exit 1
return 0

