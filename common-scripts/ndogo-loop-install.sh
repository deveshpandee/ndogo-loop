# install.sh 
# this is the common /main install script for Mojaloop vNext
# it should work across ndogo-loop (k3s) , EKS AKS and other kubernetes 
# engines and Mojaloop vNext installations 
# T Daly 
# Nov 2023

function install_vnext {
  local mlvn_deploy_target="$1"
  record_memory_use "at_start"
  print_start_banner $mlvn_deploy_target
  get_arch_of_nodes
  if [[ $mlvn_deploy_target == "ndogo-loop" ]]; then 
    check_not_inside_docker_container   # ndogo-loop only 
    set_arch  
    set_k8s_distro  
    #check_arch   # ndogo-loop only 
  elif [[ $mlvn_deploy_target == "EKS" ]]; then 
    check_access_to_cluster  # eks only 
  fi 
  check_repo_owner_not_root $VNEXT_LOCAL_REPO_DIR
  check_user
  set_k8s_version 
  check_k8s_version_is_current 
  set_logfiles 
  set_and_create_namespace 
  set_mojaloop_vnext_timeout
  printf "\n"

  if  [[ "$mode" == "update_images" ]]; then
    print "<<<< for development only >>>>>\n"
    update_k8s_images_from_docker_files 
    printf "<<<< for development only >>>>>\n"
  elif [[ "$mode" == "delete_mlvn" ]]; then
    delete_mojaloop_vnext_layer "ttk" $MANIFESTS_DIR/ttk
    delete_mojaloop_vnext_layer "reporting" $MANIFESTS_DIR/reporting
    delete_mojaloop_vnext_layer "apps" $MANIFESTS_DIR/apps
    delete_mojaloop_vnext_layer "crosscut" $MANIFESTS_DIR/crosscut
    delete_mojaloop_vnext_infra_release  
    print_end_banner $mlvn_deploy_target
  elif [[ "$mode" == "install_mlvn" ]]; then
    tstart=$(date +%s)
    printf "     <start> :  Mojaloop vNext install [%s]\n" "`date`" >> $LOGFILE
    copy_k8s_yaml_files_to_tmp
    # temp fix for mongodb helm chart so mongo-express does not hang
    perl -i.bak -pe 's/tag: 7.0/tag: 7.0.2/g' $MANIFESTS_DIR/infra/infra-helm/values.yaml
    source $HOME/mlenv/bin/activate 
    modify_local_mojaloop_vnext_yaml_and_charts  "$COMMON_SCRIPTS_DIR/configure.py" "$MANIFESTS_DIR"
    install_infra_from_local_chart $MANIFESTS_DIR/infra
    restore_mongo_demo_data $MONGO_IMPORT_DIR
    install_mojaloop_vnext_layer "crosscut" $MANIFESTS_DIR/crosscut
    install_mojaloop_vnext_layer "apps" $MANIFESTS_DIR/apps
    install_mojaloop_vnext_layer "reporting" $MANIFESTS_DIR/reporting

    if [[ "$ARCH" == "x86_64" ]] || [[ "$NODE_ARCH" == "amd64" ]]; then 
      install_mojaloop_vnext_layer "ttk" $MANIFESTS_DIR/ttk
    else
      printf "=> running on arm64 deploy ttks from /tmp/ttk\n"
      # Note today (Nov 2023) we assume that for arm64 so the TTK images are already built locally
      #      per the instructions in the readme.md this is an interim fix until we get builds for  arm64 
      #      see: https://github.com/mojaloop/project/issues/3637
      install_mojaloop_vnext_layer "ttk" /tmp/ttk
    fi
    configure_ttk  $VNEXT_LOCAL_REPO_DIR/packages/deployment/docker-compose-apps/ttk_files
    configure_elastic_search $VNEXT_LOCAL_REPO_DIR
    check_urls

    tstop=$(date +%s)
    telapsed=$(timer $tstart $tstop)
    timer_array[install_ml]=$telapsed
    print_stats
    print_success_message 
    print_end_banner $mlvn_deploy_target
  else 
    printf "** Error : wrong value for -m ** \n\n"
    showUsage
    exit 1
  fi 

}

