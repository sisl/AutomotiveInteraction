"""
	function append_to_curve!
"""
function append_to_curve!(target::Curve, newstuff::Curve)
    s_end = target[end].s
    for c in newstuff
        push!(target, CurvePt(c.pos, c.s+s_end, c.k, c.kd))
    end
    return target
end

"""
    function get_new_angle
- Does the actual angle calculation based on the x y coordinates
"""
function get_new_angle(tangent_vector::Array{Float64})
    # it might be a problem when we switch quadrants
    # use signs of tangent vector to get the quadrant of the heading 
    x = tangent_vector[1]
    y = tangent_vector[2]
    if x == 0. && y == 0.
        heading = 0.0
    elseif x == 0.
        heading = π/2 * sign(y) 
    elseif y == 0.
        heading = convert(Float64, π) # this could be either pi or -pi, but just go with pi
    elseif sign(x) == 1 && sign(y) == 1 # first quadrant
        heading = atan(y, x)
    elseif sign(x) == -1 && sign(y) == 1 # second quadrant
        heading = atan(y, x)
    elseif sign(x) == 1 && sign(y) == -1 # fourth quadrant
        heading = atan(y, x)
    elseif sign(x) == -1 && sign(y) == -1 # third quadrant
        heading = atan(y, x)
    end
    # bound_heading doesn't end up getting called cause Julia takes care of it apparently
    bound_heading(heading)

    return heading
end

"""
    function bound_heading
- Make the angle range from 0 to pi instead of going beyond
"""
function bound_heading(heading::Float64)
    if heading > π # send this to be just near -pi
        heading = -π + (heading - π)    # if heading is 3.15, then the new angle will be (-pi + (3.15-pi)) = -3.13
    elseif heading < -π # send this to be just near pi 
        heading = π + (heading + π)     # if heading is -3.15, then the new angle will be (pi + (-3.15+pi)) = 3.13
    end
    return heading
end

"""
    function append_headings
- Used create the angles and append them into the coordinates

# Examples
```julia
x_coods = [1089.07510, 1093.82626, 1101.19325, 1112.59899, 1123.96733, 1133.24150, 1146.47964]
y_coods = [936.31213, 936.92692,938.52419, 940.93865, 943.27882, 945.21039, 947.88488]
coods = hcat(x_coods,y_coods)
append_headings(coods)
```
"""
function append_headings(coordinates::Matrix{Float64})
    headings = ones(size(coordinates)[1])
    for i = 1:size(coordinates)[1]-1
        # need to make sure that math is right, and that bounds are kept
        tangent_vector = [coordinates[i+1,1]-coordinates[i,1], coordinates[i+1,2]-coordinates[i,2]]
        # @show tangent_vector
        current_heading = get_new_angle(tangent_vector)
        # @show current_heading
        headings[i] = current_heading
    end
    headings[end] = headings[end-1] # assume this is fine
    coordinates = hcat(coordinates, headings)
    return coordinates
end


# function: centerlines_txt2tracks_new
"""
    function centerlines_txt2tracks(filename)
- Reads a .txt file which contains x coords in col 1 and y coords in col2
- Returns a track, i.e. a `curve` from AutomotiveDrivingModels

# Examples
```julia
# See make_roadway_interaction()
```
"""
function centerlines_txt2tracks(filename)
    coods = readdlm(filename,',')
    coods_app = append_headings(coods) # Append with the angle
    
    mid_coods = coods_app'
    
    first_cood = VecSE2(mid_coods[1,1], mid_coods[2,1], mid_coods[3,1])
    second_cood = VecSE2(mid_coods[1,2], mid_coods[2,2], mid_coods[3,2])
    radius = 0.01
    nsamples = 20

    track = gen_bezier_curve(first_cood, second_cood, radius, radius, nsamples)
    
    nsamples = 20
    for i = 3:size(coods,1)
        turn1 = VecSE2(mid_coods[1, i-1], mid_coods[2, i-1], mid_coods[3, i-1])
        turn2 = VecSE2(mid_coods[1, i], mid_coods[2, i], mid_coods[3, i])
        curve = gen_bezier_curve(turn1, turn2, radius, radius, nsamples)
        append_to_curve!(track, curve)
    end

    return track
end


# function: read in the centerline text files and make `roadway_interaction`
"""
    function make_roadway_interaction()

- Make the `DR_CHN_Merging` roadway by reading in the centerlines in `AutomotiveInteraction.jl/dataset`
- These centerlines have been modified from the original ones in the `centerlines_DR_CHN_Merging_ZS` folder
- The long lane being merged into by on ramp was split into before and after merge point in 2 separate txt files
- Eg: `output_centerline_1.txt` was split into `centerlines_b.txt` (before merge point) and `centerlines_c.txt` (after).
- Similarly, `output_centerline_5.txt` was split into `cetnerlines_g.txt` (before) and `centerlines_h.txt` (after)
- Finally, the `output_centerline_<>.txt` had x coords in row 1 and y coords in row 2.
- The `centerlines_<>.txt` have x in col 1 and y in col 2

# Example
```julia
roadway_interaction = make_roadway_interaction()
```
"""
function make_roadway_interaction()
    roadway_interaction = Roadway()

        # Form segment 2 of the road
    track_b = centerlines_txt2tracks("../dataset/centerlines_b.txt")
    track_c = centerlines_txt2tracks("../dataset/centerlines_c.txt")
    merge_index_a_into_bc = curveindex_end(track_b)
    append_to_curve!(track_b,track_c) # b and c together become lane 1
    lane_bc = Lane(LaneTag(2,1),track_b,width=3.)
    seg_bc = RoadSegment(2,[lane_bc])

    push!(roadway_interaction.segments,seg_bc)

        # Form segment 1 of the road
    track_a = centerlines_txt2tracks("../dataset/centerlines_a.txt"); # Top most on ramp
    lane_a = Lane(LaneTag(1,1),track_a,width=3.,next=RoadIndex(merge_index_a_into_bc,LaneTag(2,1)))
    seg_a = RoadSegment(1,[lane_a])

    push!(roadway_interaction.segments,seg_a)

        # Form segment 3 of the road
    track_d = centerlines_txt2tracks("../dataset/centerlines_d.txt")
    lane_d = Lane(LaneTag(3,1),track_d,width=4.)
    seg_d = RoadSegment(3,[lane_d])
    push!(roadway_interaction.segments,seg_d)

        # Form segment 4
    track_e = centerlines_txt2tracks("../dataset/centerlines_e.txt")
    lane_e = Lane(LaneTag(4,1),track_e,width=4.)
    seg_e = RoadSegment(4,[lane_e])
    push!(roadway_interaction.segments,seg_e)

# Now going in other direction i.e. bottom left to top right direction of travel
        # Form segment 4
    track_f = centerlines_txt2tracks("../dataset/centerlines_f.txt")
    lane_f = Lane(LaneTag(5,1),track_f)
    seg_f = RoadSegment(5,[lane_f])
    push!(roadway_interaction.segments,seg_f)

        # Continue on segment 4
    track_g = centerlines_txt2tracks("../dataset/centerlines_g.txt")
    track_h = centerlines_txt2tracks("../dataset/centerlines_h.txt")
    merge_index_i_into_gh = curveindex_end(track_g)
    append_to_curve!(track_g,track_h)
    lane_gh = Lane(LaneTag(6,1),track_g,width=4.)
    seg_gh = RoadSegment(6,[lane_gh])
    push!(roadway_interaction.segments,seg_gh)

        # Form segment 6, the on ramp
    track_i = centerlines_txt2tracks("../dataset/centerlines_i.txt")
    lane_i = Lane(LaneTag(7,1),track_i,width=4.,next=RoadIndex(merge_index_i_into_gh,LaneTag(6,1)));
    seg_i = RoadSegment(7,[lane_i])
    push!(roadway_interaction.segments,seg_i)

    return roadway_interaction
end
