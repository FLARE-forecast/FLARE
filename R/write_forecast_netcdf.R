##' @title Generate netcdf output file
##' @details Function generates a netcdf file from the object that is returned by run_da_forecast()
##' @param da_forecast_output list; object that is returned by run_da_forecast()
##' @param forecast_output_directory string; full path of directory where the netcdf file will be written
##' @return None
##' @export
##' @import ncdf4
##' @import ggplot2
##' @importFrom lubridate with_tz
##' @author Quinn Thomas
##' @examples
##' \dontrun{
##' write_forecast_netcdf(da_forecast_output = da_forecast_output, forecast_output_directory = config$file_path$forecast_output_directory)
##' }
##'

write_forecast_netcdf <- function(da_forecast_output,
                                  forecast_output_directory){

  if(!dir.exists(forecast_output_directory)) {
    dir.create(forecast_output_directory, recursive = TRUE)
  }

  x <- da_forecast_output$x
  lake_depth <- da_forecast_output$lake_depth
  snow_ice_thickness <- da_forecast_output$snow_ice_thickness
  data_assimilation_flag <- da_forecast_output$data_assimilation_flag
  forecast_flag <- da_forecast_output$forecast_flag
  da_qc_flag <- da_forecast_output$da_qc_flag
  full_time <- da_forecast_output$full_time
  forecast_start_datetime <- da_forecast_output$forecast_start_datetime
  avg_surf_temp <- da_forecast_output$avg_surf_temp
  mixing_vars <- da_forecast_output$mixing_vars
  model_internal_depths <- da_forecast_output$model_internal_depths
  salt <- da_forecast_output$salt
  config <- da_forecast_output$config
  states_config <- da_forecast_output$states_config
  obs_config <- da_forecast_output$obs_config
  pars_config <- da_forecast_output$pars_config
  obs <- da_forecast_output$obs

  diagnostics <- da_forecast_output$diagnostics

  hist_days <- as.numeric(forecast_start_datetime - full_time[1])
  start_forecast_step <- 1 + hist_days

  if(!is.null(pars_config)){
    npars <- nrow(pars_config)
  }else{
    npars <- 0
  }
  nstates <- dim(da_forecast_output$x)[3] - npars

  x_efi <- aperm(x, c(1,3,2))
  diagnostics_efi <- diagnostics

  ncfname <- file.path(forecast_output_directory, paste0(da_forecast_output$save_file_name,".nc"))
  #Set dimensionsda_forecast_output
  ens <- seq(1,dim(x)[2],1)
  depths <- config$model_settings$modeled_depths
  t <- as.numeric(as.POSIXct(lubridate::with_tz(full_time),origin = '1970-01-01 00:00.00 UTC'))
  states <- seq(1,nstates,1)
  #obs_states <- seq(1,dim(obs)[3],1)

  #Set variable that states whether value is forecasted
  forecasted <- rep(1, length(t))
  forecasted[1:(hist_days + 1)] <- 0

  #Define dims
  ensdim <- ncdf4::ncdim_def("ensemble",units = "-",vals = ens, longname = 'ensemble member')
  depthdim <- ncdf4::ncdim_def("depth",units = "meters",vals = as.double(depths), longname = 'Depth from surface')
  timedim <- ncdf4::ncdim_def("time",units = 'seconds', longname = 'seconds since 1970-01-01 00:00.00 UTC',vals = t)
  snow_ice_dim <- ncdf4::ncdim_def("snow_ice_dim",units = "",vals = c(1, 2, 3), longname = 'snow ice dims')
  mixing_vars_dim <- ncdf4::ncdim_def("mixing_vars_dim",units = '', vals = seq(1, dim(mixing_vars)[1], 1), longname = 'number of mixing restart variables')
  internal_model_depths_dim <- ncdf4::ncdim_def("internal_model_depths_dim",units = '', vals = seq(1, dim(model_internal_depths)[2]), longname = 'number of possible depths that are simulated in GLM')


  #Define variables
  fillvalue <- 1e32

  def_list <- list()
  def_list[[1]] <- ncdf4::ncvar_def("temp","degC",list(timedim,depthdim, ensdim),fillvalue,'state: temperature',prec="single")
  def_list[[2]] <- ncdf4::ncvar_def("data_assimilation","dimensionless",list(timedim),missval = -99,longname = '0 = no data assimilation; 1 = data assimilated',prec="integer")
  def_list[[3]] <- ncdf4::ncvar_def("forecast","dimensionless",list(timedim),missval = -99,longname = '0 = historical; 1 = forecasted',prec="integer")
  def_list[[4]] <- ncdf4::ncvar_def("da_qc","dimensionless",list(timedim),missval = -99,longname = '0 = successful DA; 1 = no data assimilated',prec="integer")
  def_list[[5]] <- ncdf4::ncvar_def("snow_ice_thickness","meter", list(snow_ice_dim, timedim, ensdim),missval = -99,longname = 'Ice Thickness',prec="single")
  def_list[[6]] <- ncdf4::ncvar_def("lake_depth","meter",list(timedim,ensdim),missval = -99,longname = 'Depth of lake',prec="single")
  def_list[[7]] <- ncdf4::ncvar_def("avg_surf_temp","degC",list(timedim, ensdim),missval = -99,longname ='Running Average of Surface Temperature',prec="single")
  def_list[[8]] <- ncdf4::ncvar_def("mixing_vars","dimensionless",list(mixing_vars_dim, timedim, ensdim),fillvalue,longname = "variables required to restart mixing",prec="single")
  def_list[[9]] <- ncdf4::ncvar_def("model_internal_depths","meter",list(timedim, internal_model_depths_dim, ensdim),fillvalue,longname = "depths simulated by glm that are required to restart ",prec="single")
  def_list[[10]] <- ncdf4::ncvar_def("salt","g_kg",list(timedim, depthdim, ensdim),fillvalue,longname = "salt",prec="single")


  index <- 10

  for(i in 1:length(obs_config$state_names_obs)){
    long_name1 <- "observed"
    long_name2 <- obs_config$state_names_obs[i]
    long_name3 <- NULL
    long_name4 <- NULL

    long_name5 <- obs_config$target_variable[i]
    long_name6 <- obs_config$distance_threshold[i]

    for(j in 1:nrow(states_config)){
      for(k in 1:length(states_config$states_to_obs[[j]])){
        if(!is.na(states_config$states_to_obs[[j]][k])){
          if(states_config$states_to_obs[[j]][k] == i){
            if(is.null(long_name3)){
              long_name3 <- states_config$state_names[[j]]
              long_name4 <- states_config$states_to_obs_mapping[[j]][k]
            }else{
              long_name3 <- paste(long_name3, states_config$state_names[[j]],sep="-")
              long_name4 <- paste(long_name4, format(states_config$states_to_obs_mapping[[j]][k], scientific = FALSE),sep="-")
            }
          }
        }
        long_name <- paste(long_name1,long_name2,long_name3,long_name4, long_name5, long_name6, sep = ":")
      }
    }




    def_list[[index+i]] <-ncdf4::ncvar_def(paste0(obs_config$state_names_obs[i],"_observed"),obs_config$obs_units[i],list(timedim, depthdim),fillvalue,long_name,prec="single")
  }

  index <- index + length(obs_config$state_names_obs)

  if(npars > 0){
    for(par in 1:npars){
      def_list[[index+par]] <-ncdf4::ncvar_def(pars_config$par_names_save[par],pars_config$par_units[par],list(timedim,ensdim),fillvalue,paste0("parameter:",pars_config$par_names_save[par]),prec="single")
    }
  }


  if(config$include_wq){
    for(s in 2:length(states_config$state_names)){
      def_list[[index+npars+s-1]]<- ncdf4::ncvar_def(states_config$state_names[s],"mmol m-3",list(timedim,depthdim, ensdim),fillvalue,paste0("state:", states_config$state_names[s]),prec="single")
    }
  }

  if(length(config$output_settings$diagnostics_names) > 0){
    for(s in 1:length(config$output_settings$diagnostics_names)){
      def_list[[index+npars+length(states_config$state_names)-1 + s]]<- ncdf4::ncvar_def(config$output_settings$diagnostics_names[s],"-",list(timedim,depthdim, ensdim),fillvalue,paste0("diagnostic:",config$output_settings$diagnostics_names[s]),prec="single")
    }
  }

  ncout <- ncdf4::nc_create(ncfname,def_list,force_v4=T)

  # create netCDF file and put arrays
  ncdf4::ncvar_put(ncout,def_list[[1]] ,x_efi[,1:length(depths),])
  ncdf4::ncvar_put(ncout,def_list[[2]] ,as.array(data_assimilation_flag))
  ncdf4::ncvar_put(ncout,def_list[[3]] ,as.array(forecast_flag))
  ncdf4::ncvar_put(ncout,def_list[[4]] ,as.array(da_qc_flag))
  ncdf4::ncvar_put(ncout,def_list[[5]] ,snow_ice_thickness)
  ncdf4::ncvar_put(ncout,def_list[[6]] ,lake_depth)
  ncdf4::ncvar_put(ncout,def_list[[7]] ,avg_surf_temp)
  ncdf4::ncvar_put(ncout,def_list[[8]] ,mixing_vars)
  ncdf4::ncvar_put(ncout,def_list[[9]] ,model_internal_depths)
  ncdf4::ncvar_put(ncout,def_list[[10]] ,salt)

  index <- 10

  for(i in 1:length(obs_config$state_names_obs)){
    ncdf4::ncvar_put(ncout,def_list[[index + i]] ,obs[i,,])
  }

  index <- index + length(obs_config$state_names_obs)

  if(npars > 0){
    for(par in 1:npars){
      ncdf4::ncvar_put(ncout,def_list[[index + par]] ,x[,,nstates + par])
    }
  }

  if(config$include_wq){
    for(s in 2:length(states_config$state_names)){
      ncdf4::ncvar_put(ncout,def_list[[index+npars+s-1]],x_efi[,states_config$wq_start[s]:states_config$wq_end[s], ])
    }

  }

  if(length(config$output_settings$diagnostics_names) > 0){
    for(s in 1:length(config$output_settings$diagnostics_names)){
      ncdf4::ncvar_put(ncout, def_list[[index+npars+length(states_config$state_names) - 1 + s]],diagnostics_efi[s, , ,])
    }
  }

  time_of_forecast <- lubridate::with_tz(da_forecast_output$time_of_forecast, tzone = "UTC")

  #Global file metadata
  ncdf4::ncatt_put(ncout,0,"title", config$metadata$forecast_title, prec =  "text")
  ncdf4::ncatt_put(ncout,0,"forecast_iteration_id" ,da_forecast_output$forecast_iteration_id, prec =  "text")
  ncdf4::ncatt_put(ncout,0,"forecast_project_id", config$metadata$forecast_project_id, prec =  "text")
  ncdf4::ncatt_put(ncout,0,"forecast_model_id", config$metadata$model_description$forecast_model_id, prec =  "text")
  ncdf4::ncatt_put(ncout,0,"time_zone_of_simulation","UTC", prec =  "text")

  ncdf4::nc_close(ncout)

  invisible(ncfname)

}
