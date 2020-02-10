const INTERACTION_TIMESTEP = 0.1 # unit is second

"""
INTERACTIONTrajdata
The trajectory data stored in the original INTERACTION dataset format.
The dataset is a csv file with columns:
    track_id      - Int64 - Representing the id of the agent
    frame_id      - Int64 - Represents the frames in which the agent appears in the video
    timestamp_ms  - Int64 - represents the time the agent appears in the video. The unit is millisecond
    agent_type    - String - Can be person, car, truck and so on
    x             - Float64 - x position, in meter
    y             - Float64 - y position in meter
    vx            - Float64 - x velocity in m/s
    vy            - Float64 - y velocity in m/s
    psi_rad       - Float64 - yaw angle in radian
    length        - Float64 - Length of the vehicle, in meter
    width         - Float64 - Width of the vehicle, in meter

# Example
```julia
tdraw = INTERACTIONTrajdata("vehicle_tracks_000.csv");
```
"""
mutable struct INTERACTIONTrajdata
    df         :: DataFrame
    car2start  :: Dict{Int, Int}         # maps carindex to starting index in the df
    frame2cars :: Dict{Int, Vector{Int}} # maps frame to list of carids in the scene

    function INTERACTIONTrajdata(input_path::String)

        @assert(isfile(input_path))

        df = readtable(input_path, separator=',', header = true)

        car2start = Dict{Int, Int}()
        frame2cars = Dict{Int, Vector{Int}}()

        for (dfind, carid) in enumerate(df[:track_id])
            if !haskey(car2start, carid)
                car2start[carid] = dfind
            end

            frame = convert(Int, df[dfind, :frame_id])
            if !haskey(frame2cars, frame)
                frame2cars[frame] = [carid]
            else
                frame2cars[frame] = push!(frame2cars[frame], carid)
            end
        end

        new(df, car2start, frame2cars)
    end
end

# function: overload nframes from Records
"""
    Records.nframes

# Example
```julia
tdraw = INTERACTIONTrajdata("vehicle_tracks_000.csv")
nframes(tdraw)
```
"""
Records.nframes(trajdata::INTERACTIONTrajdata) = maximum(keys(trajdata.frame2cars))

# function: carsinframe for memory allocation
"""
    carsinframe(trajdata::INTERACTIONTrajdata, frame::Int)
- From the dictionary `frame2cars` which has frame number as key and all vector of car ids in that frame
as value, this function extracts the value corresponding to key given by `frame`

# Example
```julia
# Return array with car ids in frame 1
carsinframe(tdraw,1)
```
"""
carsinframe(trajdata::INTERACTIONTrajdata, frame::Int) = get(trajdata.frame2cars, frame, Int[])

# function: car_df_index - find index of car in trajdata
"""
	function car_df_index

- Given frame and carid, find index of car in trajdata
- Returns 0 if it does not exist (CAVEAT THIS IS COMMENTED OUT)

"""
function car_df_index(trajdata::INTERACTIONTrajdata, carid::Int, frame::Int)
    df = trajdata.df

    lo = trajdata.car2start[carid] # The index in the dataframe where carid first appears
    framestart = df[lo, :frame_id] # The frame number where carid first appears
    
    retval = 0

    if framestart == frame
        retval = lo
    elseif frame ≥ framestart
        retval = frame - framestart + lo
        #n_frames = df[lo, :n_frames_in_dataset]
        #if retval > lo + n_frames
        #    retval = 0
        #end
    end

    retval
end
