"""
helpers.jl
This file provides helper functions to experiments.jl, the experiment script
Most functions have the script within the doc string as example
"""

using Distributions # provides `mean`: to compute mean of particle dist over cars
using JLD # to save models
using AutomotiveInteraction

# We need a function to read in the jld file and extract metrics based on it
"""
function metrics_from_jld(f::FilteringEnvironment;filename="1.jld")
- Particle filtering based driver models stored in .jld file
- Assumes the .jld file contains driver models, veh id list, ts and te
- Extracts rmse and collision metrics by running simulations

# Example
```julia
f = FilteringEnvironment(mergeenv=MergingEnvironmentLower())
rmse_pos,rmse_vel,c_array = metrics_from_jld(f,filename="media/lower_4.jld")
```
"""
function metrics_from_jld(f::FilteringEnvironment;filename="1.jld")
    print("Metrics extraction from jld file $(filename) \n")
    # Load scenario information from jld file
    models,id_list,ts,te = JLD.load(filename,"m","veh_id_list","ts","te")
    
    scene_real = deepcopy(f.traj[ts])
    if !isempty(id_list) keep_vehicle_subset!(scene_real,id_list) end

    nticks = te-ts+1
    scene_list = simulate(scene_real,f.roadway,models,nticks,f.timestep)

    c_array = test_collision(scene_list,id_list)

    truth_list = f.traj[ts:ts+nticks]

    # rmse dict with vehicle wise rmse values
    rmse_pos_dict,rmse_vel_dict = compute_rmse(truth_list,scene_list,id_list=id_list)
    
    # Average over the vehicles
    rmse_pos = rmse_dict2mean(rmse_pos_dict)
    rmse_vel = rmse_dict2mean(rmse_vel_dict)

    return rmse_pos,rmse_vel,c_array
end

"""
- Similar function to `metrics_from_jld` but for idm based models
- `metrics_from_jld` was for particle filtering based models
- The jld file is just needed to get scenario information such as id_list,ts,te

# Arguments
- f::FilteringEnvironment
- filename: jld file
- modelmaker: function that assigns idm based models to vehicles in the scene

# Used by
- multiscenarios_idm

# Example
```julia
metrics_from_jld_idmbased(f,filename="media/lower_1.jld",modelmaker=make_IDM_models)
```
"""
function metrics_from_jld_idmbased(f::FilteringEnvironment;filename="1.jld",
modelmaker=make_cidm_models)
    print("idm based: extract veh_id_list and ts, te from $(filename) \n")
    # Load scenario information from jld file
    id_list,ts,te = JLD.load(filename,"veh_id_list","ts","te")
    
    scene_real = deepcopy(f.traj[ts])
    if !isempty(id_list) keep_vehicle_subset!(scene_real,id_list) end

    models = modelmaker(f,scene_real)

    nticks = te-ts+1
    scene_list = simulate(scene_real,f.roadway,models,nticks,f.timestep)

    c_array = test_collision(scene_list,id_list)

    truth_list = f.traj[ts:ts+nticks]

    # rmse dict with vehicle wise rmse values
    rmse_pos_dict,rmse_vel_dict = compute_rmse(truth_list,scene_list,id_list=id_list)
    
    # Average over the vehicles
    rmse_pos = rmse_dict2mean(rmse_pos_dict)
    rmse_vel = rmse_dict2mean(rmse_vel_dict)

    return rmse_pos,rmse_vel,c_array
end

"""
- Run multiple scenarios for the idm based models

# Uses
- metrics_from_jld_idmbased

# Example
```julia
rmse_pos_mat_idm, = multiscenarios_idm(mergetype="lower",modelmaker=make_IDM_models)
rmse_pos_mat_cidm, = multiscenarios_idm(mergetype="lower",modelmaker=make_cidm_models)
rmse_pos_mat_lmidm, = multiscenarios_idm(mergetype="lower",modelmaker=make_lmidm_models)
rmse_pos_mat_pf, = multiscenarios_pf(mergetype="lower")

rmse_idm = mean(rmse_pos_mat_idm,dims=2)
rmse_cidm = mean(rmse_pos_mat_cidm,dims=2)
rmse_lmidm = mean(rmse_pos_mat_lmidm,dims=2)
rmse_pf = mean(rmse_pos_mat_pf,dims=2)

pi = pgfplot_vector(rmse_idm,leg="idm");
pc = pgfplot_vector(rmse_cidm,leg="cidm");
pl = pgfplot_vector(rmse_lmidm,leg="lmidm");
ppf = pgfplot_vector(rmse_pf,leg="pf");
ax = PGFPlots.Axis([pi,pc,pl,ppf],xlabel="timestep",ylabel="rmse pos",title="multiscenario");
PGFPlots.save("media/rmse_multi4.svg",ax)
```
"""
function multiscenarios_idm(;mergetype="upper",modelmaker=make_cidm_models)
    if mergetype=="upper"
        print("Upper merge has been selected\n")
        f = FilteringEnvironment()
        num_scenarios = 5
        prefix = "upper"
    elseif mergetype == "lower"
        print("Lower merge has been selected\n")
        f=FilteringEnvironment(mergeenv=MergingEnvironmentLower())
        num_scenarios = 4
        prefix = "lower"
    end
    rmse_pos_scenariowise = []
    rmse_vel_scenariowise = []
    coll_scenariowise = []

    for i in 1:num_scenarios
        print("scenario number = $i\n")
        rmse_pos,rmse_vel,coll_array = metrics_from_jld_idmbased(f,
            filename="media/$(prefix)_$i.jld",modelmaker=modelmaker)
        push!(rmse_pos_scenariowise,rmse_pos)
        push!(rmse_vel_scenariowise,rmse_vel)
        push!(coll_scenariowise,coll_array)
    end

    rmse_pos_matrix = truncate_vecs(rmse_pos_scenariowise)
    rmse_vel_matrix = truncate_vecs(rmse_vel_scenariowise)
    coll_matrix = truncate_vecs(coll_scenariowise)
    return rmse_pos_matrix,rmse_vel_matrix,coll_matrix
end

"""
- Take multiple scenario jld files that contain models obtained using filtering
- Generate simulation trajectories and capture rmse metrics
- Uses `truncate_vecs` to make sure that rmse lengths match since scenario lengths not same

# Uses
- metrics_from_jld to extract rmse and collision by running simulations

# Example
```julia
a1,a2,a3 = multiscenarios_pf(mergetype="lower")
rmse_pos = mean(a1,dims=2)
```
"""
function multiscenarios_pf(;mergetype = "upper")
    if mergetype=="upper"
        f = FilteringEnvironment()
        num_scenarios = 5
        prefix = "upper"
    elseif mergetype == "lower"
        f=FilteringEnvironment(mergeenv=MergingEnvironmentLower())
        num_scenarios = 4
        prefix = "lower"
    end

    rmse_pos_scenariowise = []
    rmse_vel_scenariowise = []
    coll_scenariowise = []

    for i in 1:num_scenarios
        rmse_pos,rmse_vel,coll_array = metrics_from_jld(f,
        filename="media/$(prefix)_$i.jld")
        push!(rmse_pos_scenariowise,rmse_pos)
        push!(rmse_vel_scenariowise,rmse_vel)
        push!(coll_scenariowise,coll_array)
    end

    rmse_pos_matrix = truncate_vecs(rmse_pos_scenariowise)
    rmse_vel_matrix = truncate_vecs(rmse_vel_scenariowise)
    coll_matrix = truncate_vecs(coll_scenariowise)
    return rmse_pos_matrix,rmse_vel_matrix,coll_matrix
end

"""
function extract_metrics(f;ts=1,id_list=[],dur=10.,modelmaker=nothing,filename=[])

- Perform driving simulation starting from `ts` for `dur` duration.

# Arguments
- `ts`: start frame
- `id_list`: list of vehicles 
- `dur`: duration
- `modelmaker`: function that makes the models
- `filename`: provide optionally to make comparison video

# Example
```julia
f = FilteringEnvironment()
scenes,collisions = extract_metrics(f,id_list=[4,6,8,13,19,28,29],
modelmaker=make_cidm_models,filename="media/cidm_exp.mp4")
```
"""
function extract_metrics(f::FilteringEnvironment;ts=1,id_list=[],dur=10.,
modelmaker=nothing,filename=[])
    print("Run experiment from scripts being called \n")
    scene_real = deepcopy(f.traj[ts])
    if !isempty(id_list) keep_vehicle_subset!(scene_real,id_list) end

    # If modelmaker argument is provided, use that function to create models
    # Otherwise, obtaine driver models using particle filtering
    models = Dict{Int64,DriverModel}()
    if isnothing(modelmaker)
        print("Let's run particle filtering to create driver models\n")
        models,p,mean_dist_mat = obtain_driver_models(f,veh_id_list=id_list,num_p=50,ts=ts,te=ts+50)
        
        # Particle filtering progress plot
        progressplot=false
        if progressplot
            avg_over_cars = mean(mean_dist_mat,dims=2)
            avg_over_cars = reshape(avg_over_cars,length(avg_over_cars),) # for PGFPlot
            print("Making filtering progress plot\n")
            p = PGFPlots.Plots.Linear(collect(1:length(avg_over_cars)),avg_over_cars)
            ax = PGFPlots.Axis([p],xlabel = "iternum",ylabel = "avg distance",
            title = "Filtering progress")
            PGFPlots.save("media/p_prog.pdf",ax)
        end
        # Save models
        JLD.save("filtered_models.jld","models",models)
    else
        print("Lets use idm or c_idm to create driver models\n")
        models = modelmaker(f,scene_real)
    end

    nticks = Int(ceil(dur/f.timestep))
    scene_list = simulate(scene_real,f.roadway,models,nticks,f.timestep)

    c_array = test_collision(scene_list,id_list)

    truth_list = f.traj[ts:ts+nticks]

    # Make a comparison video if filename provided
    if !isempty(filename)
        video_overlay_scenelists(scene_list,truth_list,id_list=id_list,roadway=f.roadway,
            filename=filename)
    end

    # rmse dict with vehicle wise rmse values
    rmse_pos_dict,rmse_vel_dict = compute_rmse(truth_list,scene_list,id_list=id_list)
    
    # Average over the vehicles
    rmse_pos = rmse_dict2mean(rmse_pos_dict)
    rmse_vel = rmse_dict2mean(rmse_vel_dict)

    return rmse_pos,rmse_vel,c_array
end

"""
- Makes a bar plot of the fraction of collision timesteps across all scenarios
- Saves plot to `filename`

# Uses
- `frac_colliding_timesteps`: defined in `utils.jl`

# Arguments
- `coll_mat_list`: Collision matrices i.e. diff scenarios in different columns
- Order is idm,cidm,lmidm,pf

# Example
```julia
rmse_pos_mat_idm,rmse_vel_mat_idm,coll_mat_idm = 
        multiscenarios_idm(mergetype="upper",modelmaker=make_IDM_models)
rmse_pos_mat_cidm, rmse_vel_mat_cidm, coll_mat_cidm = 
        multiscenarios_idm(mergetype="upper",modelmaker=make_cidm_models)
rmse_pos_mat_lmidm, rmse_vel_mat_lmidm, coll_mat_lmidm = 
        multiscenarios_idm(mergetype="upper",modelmaker=make_lmidm_models)
rmse_pos_mat_pf, rmse_vel_mat_pf, coll_mat_pf = multiscenarios_pf(mergetype="upper")

coll_mat_list = [coll_mat_idm,coll_mat_cidm,coll_mat_lmidm,coll_mat_pf]
coll_barchart(coll_mat_list,filename = "media/coll_barchart_upper.svg")
```
"""
function coll_barchart(coll_mat_list;filename="media/test_bar.pdf")
        collfrac_idm = frac_colliding_timesteps(coll_mat_list[1])
        collfrac_cidm = frac_colliding_timesteps(coll_mat_list[2])
        collfrac_lmidm = frac_colliding_timesteps(coll_mat_list[3])
        collfrac_pf = frac_colliding_timesteps(coll_mat_list[4])

        coll_frac_list = [collfrac_idm,collfrac_cidm,collfrac_lmidm,collfrac_pf]
        ax = PGFPlots.Axis(PGFPlots.Plots.BarChart(["idm","cidm","lmidm","pf"],
                coll_frac_list),xlabel="models",ylabel="Collision Fraction")

        PGFPlots.save(filename,ax)
        print("function coll_barchart says: saved $(filename)\n")
        return nothing
end

"""
function rmse_plots_modelscompare(rmse_list;filename="media/test_rmse.pdf")
- Make rmse plots comparing different models after having found the mean rmse over scenarios

# Arguments
- `rmse_mat_list`: List with idm,cidm,lmidm,pf resulting matrices
- Each element of list is a matrix. Each column is a different scenario. Each row is a timestep

# Example
```julia
rmse_pos_mat_idm,rmse_vel_mat_idm,coll_mat_idm = 
        multiscenarios_idm(mergetype="upper",modelmaker=make_IDM_models)
rmse_pos_mat_cidm, rmse_vel_mat_cidm, coll_mat_cidm = 
        multiscenarios_idm(mergetype="upper",modelmaker=make_cidm_models)
rmse_pos_mat_lmidm, rmse_vel_mat_lmidm, coll_mat_lmidm = 
        multiscenarios_idm(mergetype="upper",modelmaker=make_lmidm_models)
rmse_pos_mat_pf, rmse_vel_mat_pf, coll_mat_pf = multiscenarios_pf(mergetype="upper")

rmse_list = [rmse_pos_mat_idm,rmse_pos_mat_cidm,rmse_pos_mat_lmidm,rmse_pos_mat_pf]
rmse_plots_modelscompare(rmse_list,filename = "media/rmse_pos_upper.svg")
```
"""
function rmse_plots_modelscompare(rmse_mat_list;filename="media/test_rmse.pdf")
        rmse_mat_idm = rmse_mat_list[1]
        rmse_mat_cidm = rmse_mat_list[2]
        rmse_mat_lmidm = rmse_mat_list[3]
        rmse_mat_pf = rmse_mat_list[4]

        rmse_idm = mean(rmse_mat_idm,dims=2)
        rmse_cidm = mean(rmse_mat_cidm,dims=2)
        rmse_lmidm = mean(rmse_mat_lmidm,dims=2)
        rmse_pf = mean(rmse_mat_pf,dims=2)
        
        pidm = pgfplot_vector(rmse_idm,leg="idm");
        pcidm = pgfplot_vector(rmse_cidm,leg="cidm");
        plmidm = pgfplot_vector(rmse_lmidm,leg="lmidm");
        ppf = pgfplot_vector(rmse_pf,leg="pf");
        ax = PGFPlots.Axis([pidm,pcidm,plmidm,ppf],xlabel="timestep",
                ylabel="rmse pos",title="Upper scenarios");
        PGFPlots.save(filename,ax)
        print("function rmse_plots_modelscompare says: saved $(filename)\n")
        return nothing
end