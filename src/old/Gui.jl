#= Possible components for the gui
    - window displaying the simulation
    - ⏵/⏸ button for the simulation 
    - slider for variables (temperature, adhesiveness, etc)
    - display for much of MH steps
    - count for number of cells
=#

function CellGUI(cpm::CellPotts{2})

    #--------Simulation Screen--------
    #Start by creating a blank figure
    fig = Figure(resolution = (1200, 1200), backgroundcolor = RGBf0(0.98, 0.98, 0.98))

    #Create observables that will change as the simulation progresses
    timestep = Node(1) #will increase by one every step
    maxLength = 1000 #Window history for plot
    energies = Node(fill(cpm.energy, maxLength)) #vector of past cpm emergies

    #The energies plot updates overtime and needs dynamic axes limits
    lim = @lift begin
        xmin = max(0, $timestep - length($energies))
        xmax = max(length($energies), $timestep)
        ymin, ymax =  extrema($energies)

        (xmin, xmax, ymin-1, ymax+1)
    end

    #Name the axes on the figure
    axSim = fig[1, 1] = Axis(fig, title = "Simulation")
    axEnergy = fig[1, 2] = Axis(fig, title = "Energy", limits = lim, height = 300, tellheight = false, valign = :top)
    # axEnergy = fig[1, 2] = Axis(fig, title = "Energy", height = 300, tellheight = false, valign = :top)
    colsize!(fig.layout, 1, Relative(2/3)) #Make cells heatmap plot relatively larger

    #The first plot will show a heatmap of the cell simulation
    # heatmap_node is an array that updates when timestep updates
    heatmap_node = @lift begin
        currentTime = $timestep
        MHStep!(cpm)
        cpm.space.nodeIDs
    end
    
    #Create the heatmap
    heatmap!(axSim,
            heatmap_node,
            show_axis = false,
            colormap = :Purples) #:Greys_3
    tightlimits!.(axSim)
    hidedecorations!.(axSim) #removes axis numbers

    #Finally, add the edge borders to the cells
    edgeConnectors = Edge2Grid(cpm.parameters.gridSize)
    (m,n) = cpm.parameters.gridSize

    #Generate all of the edge Connections by putting a point on each cell corner
    horizontal = [Point2f0(x, y) => Point2f0(x+1, y) for x in 0.5:m-0.5, y in 0.5:m+0.5]
    vertical = [Point2f0(x, y) => Point2f0(x, y+1) for y in 0.5:n-0.5, x in 0.5:n+0.5]
    points = vcat(horizontal[:],vertical[:])

    #Determine the transparency of the linesegments
    gridflip = rotl90(cpm.visual) #https://github.com/JuliaPlots/Makie.jl/issues/205

    #Cell borders are outlined in black
    black = RGBA{Float64}(0.0,0.0,0.0,1.0);
    clear = RGBA{Float64}(0.0,0.0,0.0,0.0);
    
    #Loop through all the grid connected and assign the correct color
    currentEdgeColors = [gridflip[edges[1]]==gridflip[edges[2]] ? clear : black for edges in edgeConnectors];

    #For each time update, recolor all of the edges
    lineColors_node = @lift begin
        currentTime = $timestep
        
        gridflip = rotl90(cpm.visual)

        for (i,edges) in enumerate(edgeConnectors)
            currentEdgeColors[i] = gridflip[edges[1]]==gridflip[edges[2]] ? black : black
        end

        currentEdgeColors
    end

    #Plot all of the line segments onto the simulation
    linesegments!(
        axSim,
        points,
        color = lineColors_node,
        linewidth = 2
    )

    #On the 2nd axis, plot the energies
    xvals = @lift( $lim[1]+1:$lim[2] )
    lines!(axEnergy, xvals, energies)

    #--------Buttons--------
    #Currently 2 buttons: a play/pause and a stop button
    #Place the buttons below the simulation and align to the left
    fig[2,1] = buttongrid = GridLayout(tellwidth = false, halign = :left)
    buttonsLabels = ["▶","■","Divide!","Kill"]

    #Loop through and assign button labels, width, and color
    buttongrid[1,1:length(buttonsLabels)] = [Button(
        fig,
        label = lab,
        width = 70,
        buttoncolor = :grey) for lab in buttonsLabels] 

    #Set the buttons to individual variables
    playpause, stop, cellDivideButton, cellDeathButton = contents(buttongrid)

    #If the play/pause button is clicked, change the label
    on(playpause.clicks) do clicks
        if isodd(clicks)
            playpause.label = "𝅛𝅛"
        else
            playpause.label = "▶"
        end
    end

    #partition a random cell when button is clicked 
    on(cellDivideButton.clicks) do clicks
        CellDivision!(cpm,rand(1:maximum(cpm.cells.ids)))
    end

    #Choose a random cell to kill
    on(cellDeathButton.clicks) do clicks
        CellDeath!(cpm,rand(1:maximum(cpm.cells.ids)))
    end

    display(fig)

    runsim = true
    stop.clicks[] = 0 #for stop button
    while runsim

        #Is the pause button pushed?
        if playpause.label[] == "▶"
            timestep[] += 1
            appendEnergy!(energies,cpm)
            notify(timestep)
            notify(energies)
        end

        #Has the stop button been pushed?
        if  stop.clicks[] == 1
            runsim = false
            GLMakie.destroy!(GLMakie.global_gl_screen()) #close the window
        end

        
        sleep(eps())
    end
end


function appendEnergy!(energies,cpm)
    popfirst!(energies[])
    push!(energies[], cpm.energy)
end


#This is very ugly and maybe one day I'll make it better
#This function takes in the grid dimension and returns pairs of all adjacent squares (wraps around)
# ╔═══╤═══╗
# ║ 1 │ 3 ║
# ╠═══╪═══╣
# ║ 2 │ 4 ║
# ╚═══╧═══╝
# Edge2Grid(2) = [[2, 1], [4, 3], [1, 2], [3, 4], [2, 1], [4, 3], [2, 4], [1, 3], [4, 2], [3, 1], [2, 4], [1, 3]]

function Edge2Grid(dim)
    gridIndices = LinearIndices(dim)

    x1 = reverse(reshape(gridIndices,dim),dims=1)'[:]
    x2 = circshift(x1,dim[2])

    y1 = reverse(reshape(reverse(gridIndices),dim),dims=2)[:]
    y2 = circshift(y1,dim[1])

    append!(x1,x1[1:dim[1]])
    append!(x2,x2[1:dim[1]])
    append!(y1,y1[1:dim[1]])
    append!(y2,y2[1:dim[1]])

    return [[id1,id2] for (id1,id2) in zip([x1;y1],[x2;y2])]
end

#3D method for GUI
function CellGUI(cpm::CellPotts{3})

    timestep = Node(1)
    
    # SSAO attributes are per scene (will need to play with these), too slow for animation?
    scene = Scene()

    GLMakie.enable_SSAO[] = true
    scene[:SSAO][:radius][] = 5.0
    scene[:SSAO][:blur][] = 3
    scene[:SSAO][:bias][] = 0.025

    #General voxel
    voxel = Rect3D(Point3f0(-0.5), Vec3f0(1))
   
    

    lim = FRect3D((0,0,0), cpm.parameters.gridSize)

    mesh_node = @lift begin
        currentTime = $timestep
        MHStep!(cpm)
         #Positions for the voxels
         #use the cell indices to color the cell (could also use cell type)
        [Point3f0(idx.I...) for idx in CartesianIndices(cpm.visual) if cpm.visual[idx] ≠ 0]
    end

    color_node = @lift begin
        currentTime = $timestep
        colors = filter(!isequal(0), cpm.visual)
    end
    

    meshscatter!(scene,
        mesh_node,
        marker=voxel,
        markersize=1,
        color=color_node,
        colormap=:RdYlBu_11, #see https://juliagraphics.github.io/ColorSchemes.jl/stable/basics/
        limits = lim,
        ssao=true)

    display(scene)

        runsim = true
        while runsim
            timestep[] += 1
            notify(timestep)
            sleep(eps())
        end
end


