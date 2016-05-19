
# https://github.com/stevengj/PyPlot.jl


supportedArgs(::PyPlotBackend) = [
    :annotation,
    :background_color, :foreground_color, :color_palette,
    :background_color_legend, :background_color_inside, :background_color_outside,
    :foreground_color_legend, :foreground_color_grid, :foreground_color_axis,
        :foreground_color_text, :foreground_color_border,
    :group,
    :label,
    :seriestype,
    :seriescolor, :seriesalpha,
    :linecolor, :linestyle, :linewidth, :linealpha,
    :markershape, :markercolor, :markersize, :markeralpha,
    :markerstrokewidth, :markerstrokecolor, :markerstrokealpha,
    :fillrange, :fillcolor, :fillalpha,
    :bins, :bar_width, :bar_edges,
    :n, :nc, :nr, :layout,
    :smooth,
    :title, :windowtitle, :show, :size,
    :x, :xguide, :xlims, :xticks, :xscale, :xflip, :xrotation,
    :y, :yguide, :ylims, :yticks, :yscale, :yflip, :yrotation,
    # :axis, :yrightlabel,
    :z, :zguide, :zlims, :zticks, :zscale, :zflip, :zrotation,
    :z,
    :tickfont, :guidefont, :legendfont,
    :grid, :legend, :colorbar,
    :marker_z, :levels,
    :xerror, :yerror,
    :ribbon, :quiver, :arrow,
    :orientation,
    :overwrite_figure,
    :polar,
    :normalize, :weights, :contours, :aspect_ratio,
    :match_dimensions,
    :subplot,
  ]
supportedAxes(::PyPlotBackend) = _allAxes
supportedTypes(::PyPlotBackend) = [
        :none, :line, :path, :steppre, :steppost, :shape,
        :scatter, :hist2d, :hexbin, :hist, :density,
        :bar, :sticks, #:box, :violin, :quiver,
        :hline, :vline, :heatmap, :pie, :image,
        :contour, :contour3d, :path3d, :scatter3d, :surface, :wireframe
    ]
supportedStyles(::PyPlotBackend) = [:auto, :solid, :dash, :dot, :dashdot]
supportedMarkers(::PyPlotBackend) = vcat(_allMarkers, Shape)
supportedScales(::PyPlotBackend) = [:identity, :ln, :log2, :log10]
subplotSupported(::PyPlotBackend) = true
nativeImagesSupported(::PyPlotBackend) = true


# --------------------------------------------------------------------------------------


function _initialize_backend(::PyPlotBackend)
    @eval begin
        import PyPlot
        export PyPlot
        const pycolors = PyPlot.pywrap(PyPlot.pyimport("matplotlib.colors"))
        const pypath = PyPlot.pywrap(PyPlot.pyimport("matplotlib.path"))
        const mplot3d = PyPlot.pywrap(PyPlot.pyimport("mpl_toolkits.mplot3d"))
        const pypatches = PyPlot.pywrap(PyPlot.pyimport("matplotlib.patches"))
        const pyfont = PyPlot.pywrap(PyPlot.pyimport("matplotlib.font_manager"))
        const pyticker = PyPlot.pywrap(PyPlot.pyimport("matplotlib.ticker"))
        const pycmap = PyPlot.pywrap(PyPlot.pyimport("matplotlib.cm"))
        const pynp = PyPlot.pywrap(PyPlot.pyimport("numpy"))
        const pytransforms = PyPlot.pywrap(PyPlot.pyimport("matplotlib.transforms"))
    end

    PyPlot.ioff()

    if !isa(Base.Multimedia.displays[end], Base.REPL.REPLDisplay)
        PyPlot.ioff()  # stops wierd behavior of displaying incomplete graphs in IJulia

        # # TODO: how the hell can I use PyQt4??
        # "pyqt4"=>:qt_pyqt4
        # PyPlot.backend[1] = "pyqt4"
        # PyPlot.gui[1] = :qt_pyqt4
        # PyPlot.switch_backend("Qt4Agg")

        # only turn on the gui if we want it
        if PyPlot.gui != :none
            PyPlot.pygui(true)
        end
    end
end

# -------------------------------

# convert colorant to 4-tuple RGBA
getPyPlotColor(c::Colorant, α=nothing) = map(f->float(f(convertColor(c,α))), (red, green, blue, alpha))
getPyPlotColor(cvec::ColorVector, α=nothing) = map(getPyPlotColor, convertColor(cvec, α).v)
getPyPlotColor(scheme::ColorScheme, α=nothing) = getPyPlotColor(convertColor(getColor(scheme), α))
getPyPlotColor(vec::AVec, α=nothing) = map(c->getPyPlotColor(c,α), vec) 
getPyPlotColor(c, α=nothing) = getPyPlotColor(convertColor(c, α))

function getPyPlotColorMap(c::ColorGradient, α=nothing)
    pyvals = [(v, getPyPlotColor(getColorZ(c, v), α)) for v in c.values]
    pycolors.pymember("LinearSegmentedColormap")[:from_list]("tmp", pyvals)
end

# convert vectors and ColorVectors to standard ColorGradients
# TODO: move this logic to colors.jl and keep a barebones wrapper for pyplot
getPyPlotColorMap(cv::ColorVector, α=nothing) = getPyPlotColorMap(ColorGradient(cv.v), α)
getPyPlotColorMap(v::AVec, α=nothing) = getPyPlotColorMap(ColorGradient(v), α)

# anything else just gets a bluesred gradient
getPyPlotColorMap(c, α=nothing) = getPyPlotColorMap(default_gradient(), α)

function getPyPlotCustomShading(c, z, α=nothing)
    cmap = getPyPlotColorMap(c, α)
    # sm = pycmap.pymember("ScalarMappable")(cmap = cmap)
    # sm[:set_array](z)
    # sm
    ls = pycolors.pymember("LightSource")(270,45)
    ls[:shade](z, cmap, vert_exag=0.1, blend_mode="soft")
end

# get the style (solid, dashed, etc)
function getPyPlotLineStyle(seriestype::Symbol, linestyle::Symbol)
    seriestype == :none && return " "
    linestyle == :solid && return "-"
    linestyle == :dash && return "--"
    linestyle == :dot && return ":"
    linestyle == :dashdot && return "-."
    warn("Unknown linestyle $linestyle")
    return "-"
end

function getPyPlotMarker(marker::Shape)
    x, y = shape_coords(marker)
    n = length(x)
    mat = zeros(n+1,2)
    for i=1:n
        mat[i,1] = x[i]
        mat[i,2] = y[i]
    end
    mat[n+1,:] = mat[1,:]
    pypath.pymember("Path")(mat)
end

const _path_MOVETO = UInt8(1)
const _path_LINETO = UInt8(2)
const _path_CLOSEPOLY = UInt8(79)

# see http://matplotlib.org/users/path_tutorial.html
# and http://matplotlib.org/api/path_api.html#matplotlib.path.Path
function buildPyPlotPath(x, y)
    n = length(x)
    mat = zeros(n+1, 2)
    codes = zeros(UInt8, n+1)
    lastnan = true
    for i=1:n
        mat[i,1] = x[i]
        mat[i,2] = y[i]
        nan = !ok(x[i], y[i])
        codes[i] = if nan
            _path_CLOSEPOLY
        else
            lastnan ? _path_MOVETO : _path_LINETO
        end
        lastnan = nan
    end
    codes[n+1] = _path_CLOSEPOLY
    pypath.pymember("Path")(mat, codes)
end

# get the marker shape
function getPyPlotMarker(marker::Symbol)
    marker == :none && return " "
    marker == :ellipse && return "o"
    marker == :rect && return "s"
    marker == :diamond && return "D"
    marker == :utriangle && return "^"
    marker == :dtriangle && return "v"
    marker == :cross && return "+"
    marker == :xcross && return "x"
    marker == :star5 && return "*"
    marker == :pentagon && return "p"
    marker == :hexagon && return "h"
    marker == :octagon && return "8"
    haskey(_shapes, marker) && return getPyPlotMarker(_shapes[marker])

    warn("Unknown marker $marker")
    return "o"
end

# getPyPlotMarker(markers::AVec) = map(getPyPlotMarker, markers)
function getPyPlotMarker(markers::AVec)
    warn("Vectors of markers are currently unsupported in PyPlot: $markers")
    getPyPlotMarker(markers[1])
end

# pass through
function getPyPlotMarker(marker::AbstractString)
    @assert length(marker) == 1
    marker
end

function getPyPlotStepStyle(seriestype::Symbol)
    seriestype == :steppost && return "steps-post"
    seriestype == :steppre && return "steps-pre"
    return "default"
end

# untested... return a FontProperties object from a Plots.Font
function getPyPlotFont(font::Font)
    pyfont.pymember("FontProperties")(
        family = font.family,
        size = font.size
    )
end

function get_locator_and_formatter(vals::AVec)
    pyticker.pymember("FixedLocator")(1:length(vals)), pyticker.pymember("FixedFormatter")(vals)
end

function add_pyfixedformatter(cbar, vals::AVec)
    cbar[:locator], cbar[:formatter] = get_locator_and_formatter(vals)
    cbar[:update_ticks]()
end

# ---------------------------------------------------------------------------
# Figure utils -- F*** matplotlib for making me work so hard to figure this crap out

# the drawing surface
canvas(fig) = fig[:canvas]

# the object controlling draw commands
renderer(fig) = canvas(fig)[:get_renderer]()

# draw commands... paint the screen (probably updating internals too)
drawfig(fig) = fig[:draw](renderer(fig))
drawax(ax) = ax[:draw](renderer(ax[:get_figure]()))

# bbox(obj) = obj[:get_window_extent](renderer(obj[:get_figure]()))
# pos(obj) = obj[:get_position]()

# # merge a list of bounding boxes together to become the area that surrounds them all
# bbox_union(bboxes) = pytransforms.Bbox[:union](bboxes)

# function py_bbox_pct(obj)
#     pybbox_pixels = obj[:get_window_extent]()
#     fig = obj[:get_figure]()
#     pybbox_pct = pybbox_pixels[:inverse_transformed](fig[:transFigure])
#     left, right, bottom, top = pybbox_pct[:get_points]()
#     BoundingBox(left, bottom, right, top)
# end

get_extents(obj) = obj[:get_window_extent]()[:get_points]()

function py_bbox_fig(fig)
    fl, fr, fb, ft = get_extents(fig)
    BoundingBox(0px, 0px, (fr-fl)*px, (ft-fb)*px)
end
py_bbox_fig(plt::Plot) = py_bbox_fig(plt.o)

# compute a bounding box (with origin top-left), however pyplot gives coords with origin bottom-left
function py_bbox(obj)
    fl, fr, fb, ft = get_extents(obj[:get_figure]())
    # @show fl, fr, fb, ft
    l, r, b, t = get_extents(obj)
    # @show l, r, b, t, obj
    BoundingBox(l*px, (ft-t)*px, (r-l)*px, (t-b)*px)
end


function py_bbox_ticks(ax, letter)
    # fig = ax[:get_figure]()
    # @show fig
    labels = ax[symbol("get_"*letter*"ticklabels")]()
    # @show labels
    # bboxes = []
    bbox_union = defaultbox
    for lab in labels
        # @show lab,lab[:get_text]()
        bbox = py_bbox(lab)
        bbox_union = bbox_union + bbox
        # @show letter,bbox bbox_union
        # @show bbox_union
    end
    bbox_union
end

function py_bbox_axislabel(ax, letter)
    pyaxis_label = ax[symbol("get_"*letter*"axis")]()[:label]
    py_bbox(pyaxis_label)
end

# get a bounding box for the whole axis
function py_bbox_axis(ax, letter)
    ticks = py_bbox_ticks(ax, letter)
    labels = py_bbox_axislabel(ax, letter)
    # letter == "x" && @show ticks labels ticks+labels
    ticks + labels
end

# get a bounding box for the title area
function py_bbox_title(ax)
    bb = defaultbox
    for s in (:title, :_left_title, :_right_title)
        bb = bb + py_bbox(ax[s])
    end
    bb
end

# TODO: need to compute each of these by subtracting the plotarea position from
# the most extreme guide/axis in each direction.  Can pass method (left,top,right,bottom)
# and aggregation (minimum or maximum) into a method to do this.

min_padding_left(layout::Subplot{PyPlotBackend})   = compute_min_padding(layout, left,   1)
min_padding_top(layout::Subplot{PyPlotBackend})    = compute_min_padding(layout, top,    1)
min_padding_right(layout::Subplot{PyPlotBackend})  = compute_min_padding(layout, right, -1)
min_padding_bottom(layout::Subplot{PyPlotBackend}) = compute_min_padding(layout, bottom,-1)

# loop over the guides and axes and compute how far they "stick out" from the plot area,
# so that we know the minimum padding we need to avoid cropping and overlapping text.
# `func` is one of (left,top,right,bottom), and we multiply by 1 or -1 depending on direction
function compute_min_padding(sp::Subplot{PyPlotBackend}, func::Function, mult::Number)
    ax = sp.o
    plotbb = py_bbox(ax)
    # @show func, mult plotbb
    # @show func, py_bbox_axis(ax, "x")
    padding = 0mm
    for bb in (py_bbox_axis(ax, "x"),
               py_bbox_axis(ax, "y"),
               py_bbox_title(ax))
        diff = func(plotbb) - func(bb)
        # @show diff,bb
        if ispositive(width(bb)) && ispositive(height(bb))
            padding = max(padding, mult * diff)
        end
        # @show padding
    end

    # if func == top
    #     titlebbox = py_bbox_title(ax)
    #     padding = max(padding, height(titlebbox))
    #     @show titlebbox height(titlebbox),padding
    # end

    padding
end

# xaxis_height(sp::Subplot{PyPlotBackend}) = height(py_bbox_axis(sp.o,"x"))
# yaxis_width(sp::Subplot{PyPlotBackend}) = width(py_bbox_axis(sp.o,"y"))
# title_height(sp::Subplot{PyPlotBackend}) = height(py_bbox_title(sp.o))

# # note: this overrides the default version to allow for labels that stick out the sides
# # bounding box (relative to canvas) for plot area
# # note: we assume the x axis is on the left, and y axis is on the bottom
# # TODO: really the padding below should be part of the freespace calc, and we should probably
# #       cache the plotarea bbox while we're doing that (need to add plotarea field to Subplot)
# function plotarea_bbox(sp::Subplot{PyPlotBackend})
#     ax = sp.o
#     plot_bb = py_bbox(ax)
#     xbb = py_bbox_axis(ax, "x")
#     ybb = py_bbox_axis(ax, "y")
#     titbb = py_bbox_title(ax)
#     items = [xbb, ybb, titbb]
#     # TODO: add in margin/padding from sp.attr
#     leftpad   = max(0mm, left(plot_bb) - minimum(map(left, items)))
#     bottompad = max(0mm, bottom(plot_bb) - minimum(map(bottom, items)))
#     rightpad  = max(0mm, maximum(map(right, items)) - right(plot_bb))
#     toppad    = max(0mm, maximum(map(top, items)) - top(plot_bb))
#     crop(bbox(sp), BoundingBox(leftpad, bottompad,
#                                width(sp) - rightpad - leftpad,
#                                height(sp) - toppad - bottompad))
# end

# ---------------------------------------------------------------------------

function update_position!(sp::Subplot{PyPlotBackend})
    ax = sp.o
    figw, figh = size(py_bbox_fig(sp.plt))

    # plot_bb = plotarea_bbox(sp)
    plot_bb = sp.plotarea
    # @show sp.bbox plot_bb
    # l = float(left(plot_bb) / px) / figw
    # b = float(bottom(plot_bb) / px) / figh
    # w = float(width(plot_bb) / px) / figw
    mms = Float64[f(plot_bb).value for f in (left, bottom, width, height)]

    mms[2] = figh.value - mms[2]
    # @show mms
    pcts = mms ./ Float64[figw.value, figh.value, figw.value, figh.value]
    # @show pcts
    ax[:set_position](pcts)
end

# each backend should set up the subplot here
function _initialize_subplot(plt::Plot{PyPlotBackend}, sp::Subplot{PyPlotBackend})
    fig = plt.o
    # add a new axis, and force it to create a new one by setting a distinct label
    proj = sp.attr[:projection]
    ax = fig[:add_axes](
        [0,0,1,1],
        label = string(gensym()),
        projection = (proj in (nothing,:none) ? nothing : string(proj))
    )
    # projection =
    # ax = fig[:add_subplot](111, projection = _py_projections[sp.attr[:projection]])
    # for axis in (:xaxis, :yaxis)
    #     ax[axis][:_autolabelpos] = false
    # end
    sp.o = ax
end

# ---------------------------------------------------------------------------

# these can probably be removed eventually... right now they're just keeping things working before cleanup
# getAxis(plt::Plot{PyPlotBackend}, subplot::Subplot = plt.subplots[1]) = subplot.o

getAxis(sp::Subplot) = sp.o

function getAxis(plt::Plot{PyPlotBackend}, series::Series)
    sp = get_subplot(plt, get(series.d, :subplot, 1))
    getAxis(sp)
end

# getLeftAxis(plt::Plot{PyPlotBackend}, subplot::Subplot = plt.subplots[1]) = getAxis(plt, subplot)
getfig(o) = o

# ---------------------------------------------------------------------------

# type PyPlotAxisWrapper
#     ax
#     rightax
#     fig
#     kwargs  # for add_subplot
# end
#
# getfig(wrap::PyPlotAxisWrapper) = wrap.fig
#
#
#
# # get a reference to the correct axis
# function getLeftAxis(wrap::PyPlotAxisWrapper)
#     if wrap.ax == nothing
#         axes = wrap.fig.o[:axes]
#         if isempty(axes)
#             return wrap.fig.o[:add_subplot](111; wrap.kwargs...)
#         end
#         axes[1]
#     else
#         wrap.ax
#     end
# end
#
# function getRightAxis(wrap::PyPlotAxisWrapper)
#     if wrap.rightax == nothing
#         wrap.rightax = getLeftAxis(wrap)[:twinx]()
#     end
#     wrap.rightax
# end
#
# getLeftAxis(plt::Plot{PyPlotBackend}) = getLeftAxis(plt.o)
# getRightAxis(plt::Plot{PyPlotBackend}) = getRightAxis(plt.o)
# # getAxis(plt::Plot{PyPlotBackend}, axis::Symbol) = (axis == :right ? getRightAxis : getLeftAxis)(plt)


function handleSmooth(plt::Plot{PyPlotBackend}, ax, d::KW, smooth::Bool)
    if smooth
        xs, ys = regressionXY(d[:x], d[:y])
        ax[:plot](xs, ys,
                  # linestyle = getPyPlotLineStyle(:path, :dashdot),
                  color = getPyPlotColor(d[:linecolor]),
                  linewidth = 2
                 )
    end
end
handleSmooth(plt::Plot{PyPlotBackend}, ax, d::KW, smooth::Real) = handleSmooth(plt, ax, d, true)

# ---------------------------------------------------------------------------

# makePyPlotCurrent(wrap::PyPlotAxisWrapper) = wrap.ax == nothing ? PyPlot.figure(wrap.fig.o[:number]) : nothing
# makePyPlotCurrent(plt::Plot{PyPlotBackend}) = plt.o == nothing ? nothing : makePyPlotCurrent(plt.o)
#
#
# function _before_add_series(plt::Plot{PyPlotBackend})
#     makePyPlotCurrent(plt)
# end


# ------------------------------------------------------------------

function pyplot_figure(plotargs::KW)
    w,h = map(px2inch, plotargs[:size])

    # reuse the current figure?
    fig = if plotargs[:overwrite_figure]
        PyPlot.gcf()
    else
        PyPlot.figure()
    end

    # update the specs
    fig[:set_size_inches](w, h, forward = true)
    fig[:set_facecolor](getPyPlotColor(plotargs[:background_color_outside]))
    fig[:set_dpi](DPI)
    # fig[:set_tight_layout](true)

    # clear the figure
    PyPlot.clf()

    # resize the window
    PyPlot.plt[:get_current_fig_manager]()[:resize](plotargs[:size]...)
    fig
end

function pyplot_3d_setup!(wrap, d)
    if trueOrAllTrue(st -> st in _3dTypes, get(d, :seriestype, :none))
        push!(wrap.kwargs, (:projection, "3d"))
    end
end

# ---------------------------------------------------------------------------

function _create_backend_figure(plt::Plot{PyPlotBackend})
    fig = pyplot_figure(plt.plotargs)
    # TODO: handle 3d and polar
    fig
end

# function _create_backend_figure(plt::Plot)
#     if haskey(plt.plotargs, :subplot)
#         wrap = nothing
#     else
#         wrap = PyPlotAxisWrapper(nothing, nothing, pyplot_figure(plt.plotargs), [])
#         pyplot_3d_setup!(wrap, plt.plotargs)
#         if get(plt.plotargs, :polar, false)
#             push!(wrap.kwargs, (:polar, true))
#         end
#     end
#     wrap
#     # plt = Plot(wrap, pkg, 0, plt.plotargs, KW[])
#     # plt
# end

# ---------------------------------------------------------------------------

function fix_xy_lengths!(plt::Plot{PyPlotBackend}, d::KW)
    x, y = d[:x], d[:y]
    nx, ny = length(x), length(y)
    if !isa(get(d, :z, nothing), Surface) && nx != ny
        if nx < ny
            d[:x] = Float64[x[mod1(i,nx)] for i=1:ny]
        else
            d[:y] = Float64[y[mod1(i,ny)] for i=1:nx]
        end
    end
end

# total hack due to PyPlot bug (see issue #145).
# hack: duplicate the color vector when the total rgba fields is the same as the series length
function color_fix(c, x)
    if (typeof(c) <: AbstractArray && length(c)*4 == length(x)) ||
                    (typeof(c) <: Tuple && length(x) == 4)
        vcat(c, c)
    else
        c
    end
end

pylinecolor(d::KW)          = getPyPlotColor(d[:linecolor], d[:linealpha])
pymarkercolor(d::KW)        = getPyPlotColor(d[:markercolor], d[:markeralpha])
pymarkerstrokecolor(d::KW)  = getPyPlotColor(d[:markerstrokecolor], d[:markerstrokealpha])
pyfillcolor(d::KW)          = getPyPlotColor(d[:fillcolor], d[:fillalpha])

pylinecolormap(d::KW)       = getPyPlotColorMap(d[:linecolor], d[:linealpha])
pymarkercolormap(d::KW)     = getPyPlotColorMap(d[:markercolor], d[:markeralpha])
pyfillcolormap(d::KW)       = getPyPlotColorMap(d[:fillcolor], d[:fillalpha])

# function _add_series(pkg::PyPlotBackend, plt::Plot, d::KW)
# TODO: change this to accept Subplot??
function _add_series(plt::Plot{PyPlotBackend}, series::Series)
    d = series.d
    st = d[:seriestype]
    if !(st in supportedTypes(plt.backend))
        error("seriestype $(st) is unsupported in PyPlot.  Choose from: $(supportedTypes(plt.backend))")
    end

    # 3D plots have a different underlying Axes object in PyPlot
    # TODO: BUG: this adds to kwargs but never changes anything... source of subplot(wireframe(...)) bug?
    if st in _3dTypes && isempty(plt.o.kwargs)
        push!(plt.o.kwargs, (:projection, "3d"))
    end

    # PyPlot doesn't handle mismatched x/y
    fix_xy_lengths!(plt, d)

    # ax = getAxis(plt, d[:axis])
    ax = getAxis(plt, series)
    x, y, z = d[:x], d[:y], d[:z]
    # @show typeof((x,y,z))
    xyargs = (st in _3dTypes ? (x,y,z) : (x,y))

    # handle zcolor and get c/cmap
    extrakw = KW()

    # holds references to any python object representing the matplotlib series
    handles = []
    needs_colorbar = false
    discrete_colorbar_values = nothing


    # pass in an integer value as an arg, but a levels list as a keyword arg
    levels = d[:levels]
    levelargs = if isscalar(levels)
        (levels)
    elseif isvector(levels)
        extrakw[:levels] = levels
        ()
    else
        error("Only numbers and vectors are supported with levels keyword")
    end

    # for each plotting command, optionally build and add a series handle to the list

    # line plot
    if st in (:path, :line, :scatter, :path3d, :scatter3d, :steppre, :steppost)
        if d[:linewidth] > 0
            handle = ax[:plot](xyargs...;
                label = d[:label],
                zorder = plt.n,
                color = pylinecolor(d),
                linewidth = d[:linewidth],
                linestyle = getPyPlotLineStyle(st, d[:linestyle]),
                solid_capstyle = "round",
                # dash_capstyle = "round",
                drawstyle = getPyPlotStepStyle(st)
            )[1]
            push!(handles, handle)

            a = d[:arrow]
            if a != nothing && !is3d(d)  # TODO: handle 3d later
                if typeof(a) != Arrow
                    warn("Unexpected type for arrow: $(typeof(a))")
                else
                    arrowprops = KW(
                        :arrowstyle => "simple,head_length=$(a.headlength),head_width=$(a.headwidth)",
                        :shrinkA => 0,
                        :shrinkB => 0,
                        :edgecolor => pylinecolor(d),
                        :facecolor => pylinecolor(d),
                        :linewidth => d[:linewidth],
                        :linestyle => getPyPlotLineStyle(st, d[:linestyle]),
                    )
                    add_arrows(x, y) do xyprev, xy
                        ax[:annotate]("",
                            xytext = (0.001xyprev[1] + 0.999xy[1], 0.001xyprev[2] + 0.999xy[2]),
                            xy = xy,
                            arrowprops = arrowprops
                        )
                    end
                end
            end
        end
    end

    if st == :bar
        extrakw[isvertical(d) ? :width : :height] = d[:bar_width]
        handle = ax[isvertical(d) ? :bar : :barh](x, y;
            label = d[:label],
            zorder = plt.n,
            color = pyfillcolor(d),
            edgecolor = pylinecolor(d),
            linewidth = d[:linewidth],
            align = d[:bar_edges] ? "edge" : "center",
            extrakw...
        )[1]
        push!(handles, handle)
    end

    if st == :sticks
        extrakw[isvertical(d) ? :width : :height] = 0.0
        handle = ax[isvertical(d) ? :bar : :barh](x, y;
            label = d[:label],
            zorder = plt.n,
            color = pylinecolor(d),
            edgecolor = pylinecolor(d),
            linewidth = d[:linewidth],
            align = "center",
            extrakw...
        )[1]
        push!(handles, handle)
    end

    # add markers?
    if d[:markershape] != :none && st in (:path, :line, :scatter, :path3d,
                                          :scatter3d, :steppre, :steppost,
                                          :bar, :sticks)
        extrakw = KW()
        if d[:marker_z] == nothing
            extrakw[:c] = color_fix(pymarkercolor(d), x)
        else
            extrakw[:c] = convert(Vector{Float64}, d[:marker_z])
            extrakw[:cmap] = pymarkercolormap(d)
            needs_colorbar = true
        end
        xyargs = if st in (:bar, :sticks) && !isvertical(d)
            (y, x)
        else
            xyargs
        end
        handle = ax[:scatter](xyargs...;
            label = d[:label],
            zorder = plt.n + 0.5,
            marker = getPyPlotMarker(d[:markershape]),
            s = d[:markersize] .^ 2,
            edgecolors = pymarkerstrokecolor(d),
            linewidths = d[:markerstrokewidth],
            extrakw...
        )
        push!(handles, handle)
    end

    if st == :hist
        handle = ax[:hist](y;
            label = d[:label],
            zorder = plt.n,
            color = pyfillcolor(d),
            edgecolor = pylinecolor(d),
            linewidth = d[:linewidth],
            bins = d[:bins],
            normed = d[:normalize],
            weights = d[:weights],
            orientation = (isvertical(d) ? "vertical" : "horizontal"),
            histtype = (d[:bar_position] == :stack ? "barstacked" : "bar")
        )[1]
        push!(handles, handle)
    end

    if st == :hist2d
        handle = ax[:hist2d](x, y;
            label = d[:label],
            zorder = plt.n,
            bins = d[:bins],
            normed = d[:normalize],
            weights = d[:weights],
            cmap = pyfillcolormap(d)  # applies to the pcolorfast object
        )[4]
        push!(handles, handle)
        needs_colorbar = true
    end

    if st == :hexbin
        handle = ax[:hexbin](x, y;
            label = d[:label],
            zorder = plt.n,
            gridsize = d[:bins],
            linewidths = d[:linewidth],
            edgecolors = pylinecolor(d),
            cmap = pyfillcolormap(d)  # applies to the pcolorfast object
        )
        push!(handles, handle)
        needs_colorbar = true
    end

    if st in (:hline,:vline)
        for yi in d[:y]
            func = ax[st == :hline ? :axhline : :axvline]
            handle = func(yi;
                linewidth=d[:linewidth],
                color=pylinecolor(d),
                linestyle=getPyPlotLineStyle(st, d[:linestyle])
            )
            push!(handles, handle)
        end
    end

    if st in (:contour, :contour3d)
        # z = z.surf'
        z = transpose_z(d, z.surf)
        needs_colorbar = true


        if st == :contour3d
            extrakw[:extend3d] = true
        end

        # contour lines
        handle = ax[:contour](x, y, z, levelargs...;
            label = d[:label],
            zorder = plt.n,
            linewidths = d[:linewidth],
            linestyles = getPyPlotLineStyle(st, d[:linestyle]),
            cmap = pylinecolormap(d),
            extrakw...
        )
        push!(handles, handle)

        # contour fills
        # if st == :contour
        handle = ax[:contourf](x, y, z, levelargs...;
            label = d[:label],
            zorder = plt.n + 0.5,
            cmap = pyfillcolormap(d),
            extrakw...
        )
        push!(handles, handle)
        # end
    end

    if st in (:surface, :wireframe)
        if typeof(z) <: AbstractMatrix || typeof(z) <: Surface
            x, y, z = map(Array, (x,y,z))
            if !ismatrix(x) || !ismatrix(y)
                x = repmat(x', length(y), 1)
                y = repmat(y, 1, length(d[:x]))
            end
            # z = z'
            z = transpose_z(d, z)
            if st == :surface
                if d[:marker_z] != nothing
                    extrakw[:facecolors] = getPyPlotCustomShading(d[:fillcolor], d[:marker_z], d[:fillalpha])
                    extrakw[:shade] = false
                else
                    extrakw[:cmap] = pyfillcolormap(d)
                    needs_colorbar = true
                end
            end
            handle = ax[st == :surface ? :plot_surface : :plot_wireframe](x, y, z;
                label = d[:label],
                zorder = plt.n,
                rstride = 1,
                cstride = 1,
                linewidth = d[:linewidth],
                edgecolor = pylinecolor(d),
                extrakw...
            )
            push!(handles, handle)

            # contours on the axis planes
            if d[:contours]
                for (zdir,mat) in (("x",x), ("y",y), ("z",z))
                    offset = (zdir == "y" ? maximum : minimum)(mat)
                    handle = ax[:contourf](x, y, z, levelargs...;
                        zdir = zdir,
                        cmap = pyfillcolormap(d),
                        offset = (zdir == "y" ? maximum : minimum)(mat)  # where to draw the contour plane
                    )
                    push!(handles, handle)
                    needs_colorbar = true
                end
            end

            # no colorbar if we are creating a surface LightSource
            if haskey(extrakw, :facecolors)
                needs_colorbar = false
            end

        elseif typeof(z) <: AbstractVector
            # tri-surface plot (http://matplotlib.org/mpl_toolkits/mplot3d/tutorial.html#tri-surface-plots)
            handle = ax[:plot_trisurf](x, y, z;
                label = d[:label],
                zorder = plt.n,
                cmap = pyfillcolormap(d),
                linewidth = d[:linewidth],
                edgecolor = pylinecolor(d)
            )
            push!(handles, handle)
            needs_colorbar = true
        else
            error("Unsupported z type $(typeof(z)) for seriestype=$st")
        end
    end

    if st == :image
        img = Array(transpose_z(d, z.surf))
        z = if eltype(img) <: Colors.AbstractGray
            float(img)
        elseif eltype(img) <: Colorant
            map(c -> Float64[red(c),green(c),blue(c)], img)
        else
            z  # hopefully it's in a data format that will "just work" with imshow
        end
        handle = ax[:imshow](z;
            zorder = plt.n
        )
        push!(handles, handle)
    end

    if st == :heatmap
        x, y, z = heatmap_edges(x), heatmap_edges(y), transpose_z(d, z.surf)
        if !(eltype(z) <: Number)
            z, discrete_colorbar_values = indices_and_unique_values(z)
        end
        handle = ax[:pcolormesh](x, y, z;
            label = d[:label],
            zorder = plt.n,
            cmap = pyfillcolormap(d),
            edgecolors = (d[:linewidth] > 0 ? pylinecolor(d) : "face")
        )
        push!(handles, handle)
        needs_colorbar = true
    end

    if st == :shape
        path = buildPyPlotPath(x, y)
        patches = pypatches.pymember("PathPatch")(path;
            label = d[:label],
            zorder = plt.n,
            edgecolor = pymarkerstrokecolor(d),
            facecolor = pymarkercolor(d),
            linewidth = d[:markerstrokewidth],
            fill = true
        )
        handle = ax[:add_patch](patches)
        push!(handles, handle)
    end

    if st == :pie
        handle = ax[:pie](y;
            # label = d[:label],
            # colors = # a vector of colors?
            labels = x
        )
        push!(handles, handle)
    end

    d[:serieshandle] = handles

    # smoothing
    handleSmooth(plt, ax, d, d[:smooth])

    # add the colorbar legend
    if needs_colorbar && attr(d[:subplot], :colorbar) != :none
        # cbar = PyPlot.colorbar(handles[end], ax=ax)

        # do we need a discrete colorbar?
        if discrete_colorbar_values == nothing
            PyPlot.colorbar(handles[end], ax=ax)
        else
            # add_pyfixedformatter(cbar, discrete_colorbar_values)
            locator, formatter = get_locator_and_formatter(discrete_colorbar_values)
            vals = 1:length(discrete_colorbar_values)
            PyPlot.colorbar(handles[end],
                ax = ax,
                ticks = locator,
                format = formatter,
                boundaries = vcat(0, vals + 0.5),
                values = vals
            )
        end
    end

    # this sets the bg color inside the grid
    ax[:set_axis_bgcolor](getPyPlotColor(d[:subplot].attr[:background_color_inside]))

    # handle area filling
    fillrange = d[:fillrange]
    if fillrange != nothing && st != :contour
        f, dim1, dim2 = if isvertical(d)
            :fill_between, x, y
        else
            :fill_betweenx, y, x
        end
        args = if typeof(fillrange) <: Union{Real, AVec}
            dim1, fillrange, dim2
        else
            dim1, fillrange...
        end

        handle = ax[f](args...;
            zorder = plt.n,
            facecolor = pyfillcolor(d),
            linewidths = 0
        )
        push!(handles, handle)
    end

    # push!(plt.seriesargs, d)
    # plt
end


# -----------------------------------------------------------------


# # given a dimension (:x, :y, or :z), loop over the seriesargs KWs to find the min/max of the underlying data
# function minmaxseries(series_list, dimension, axis)
#     lo, hi = Inf, -Inf
#     for series in series_list
#         series.d[:axis] == axis || continue
#         v = series.d[dimension]
#         if length(v) > 0
#             vlo, vhi = extrema(v)
#             lo = min(lo, vlo)
#             hi = max(hi, vhi)
#         end
#     end
#     if lo == hi
#         hi = if lo == 0
#             1e-6
#         else
#             hi + min(abs(1e-2hi), 1e-6)
#         end
#     end
#     lo, hi
# end
#
# # TODO: this needs to handle one-sided fixed limits
# # TODO: this should be handled within the Axis type
# function set_lims!(plt::Plot{PyPlotBackend}, axis::Symbol)
#     ax = getAxis(plt, axis)
#     pargs = plt.plotargs
#     if pargs[:xlims] == :auto
#         ax[pargs[:polar] ? :set_tlim : :set_xlim](minmaxseries(plt.series_list, :x, axis)...)
#     end
#     if pargs[:ylims] == :auto
#         ax[pargs[:polar] ? :set_rlim : :set_ylim](minmaxseries(plt.series_list, :y, axis)...)
#     end
#     if pargs[:zlims] == :auto && haskey(ax, :set_zlim)
#         ax[:set_zlim](minmaxseries(plt.series_list, :z, axis)...)
#     end
# end

# --------------------------------------------------------------------------

# TODO: d[:serieshandle] should really be a list of handles... then we should set
# the x/y data for each handle (for example, plot and scatter)

function setxy!{X,Y}(plt::Plot{PyPlotBackend}, xy::Tuple{X,Y}, i::Integer)
    d = plt.series_list[i].d
    d[:x], d[:y] = xy
    for handle in d[:serieshandle]
        try
            handle[:set_data](xy...)
        catch
            handle[:set_offsets](hcat(xy...))
        end
    end
    # set_lims!(plt, plt.series_list[i])
    plt
end


function setxyz!{X,Y,Z}(plt::Plot{PyPlotBackend}, xyz::Tuple{X,Y,Z}, i::Integer)
    d = plt.series_list[i].d
    d[:x], d[:y], d[:z] = xyz
    for handle in d[:serieshandle]
        handle[:set_data](d[:x], d[:y])
        handle[:set_3d_properties](d[:z])
    end
    # set_lims!(plt, plt.series_list[i])
    plt
end

# --------------------------------------------------------------------------

function addPyPlotLims(ax, lims, letter)
    lims == :auto && return
    ltype = limsType(lims)
    if ltype == :limits
        setf = ax[symbol("set_", letter, "lim")]
        l1, l2 = lims
        if isfinite(l1)
            letter == "x" ? setf(left = l1) : setf(bottom = l1)
        end
        if isfinite(l2)
            letter == "x" ? setf(right = l2) : setf(top = l2)
        end
    else
        error("Invalid input for $letter: ", lims)
    end
end

function addPyPlotTicks(ax, ticks, letter)
    ticks == :auto && return
    axis = ax[symbol(letter,"axis")]
    # tickfunc = symbol("set_", letter, "ticks")
    # labfunc = symbol("set_", letter, "ticklabels")
    if ticks == :none || ticks == nothing
        # ax[][:set_major_locator]
        # ax[tickfunc]([])
        # ax[labfunc]([])
        kw = KW()
        for dir in (:top,:bottom,:left,:right)
            kw[dir] = kw[symbol(:label,dir)] = "off"
        end
        axis[:set_tick_params](;which="both", kw...)
        return
    end

    ttype = ticksType(ticks)
    if ttype == :ticks
        # ax[tickfunc](ticks)
        axis[:set_ticks](ticks)
    elseif ttype == :ticks_and_labels
        # ax[tickfunc](ticks[1])
        # ax[labfunc](ticks[2])
        axis[:set_ticks](ticks[1])
        axis[:set_ticklabels](ticks[2])
    else
        error("Invalid input for $(isx ? "xticks" : "yticks"): ", ticks)
    end
end

function applyPyPlotScale(ax, scaleType::Symbol, letter)
    func = ax[symbol("set_", letter, "scale")]
    scaleType == :identity && return func("linear")
    scaleType == :ln && return func("log", basex = e, basey = e)
    scaleType == :log2 && return func("log", basex = 2, basey = 2)
    scaleType == :log10 && return func("log", basex = 10, basey = 10)
    warn("Unhandled scaleType: ", scaleType)
end


function updateAxisColors(ax, a::Axis)
    for (loc, spine) in ax[:spines]
        spine[:set_color](getPyPlotColor(a[:foreground_color_border]))
    end
    # for letter in ("x", "y", "z")
        axissym = symbol(a[:letter], :axis)
        if haskey(ax, axissym)
            ax[:tick_params](axis=string(a[:letter]), which="both",
                             colors=getPyPlotColor(a[:foreground_color_axis]),
                             labelcolor=getPyPlotColor(a[:foreground_color_text]))
            ax[axissym][:label][:set_color](getPyPlotColor(a[:foreground_color_guide]))
        end
    # end
end

# function usingRightAxis(plt::Plot{PyPlotBackend})
#     any(args -> args[:axis] in (:right,:auto), plt.seriesargs)
# end


# --------------------------------------------------------------------------


function _update_plot(plt::Plot{PyPlotBackend}, d::KW)
    # @show d
    # figorax = plt.o
    # ax = getLeftAxis(figorax)
    for sp in plt.subplots
        spargs = sp.attr
        ax = getAxis(sp)
        # ticksz = get(d, :tickfont, plt.plotargs[:tickfont]).pointsize
        # guidesz = get(d, :guidefont, spargs[:guidefont]).pointsize

        # title
        if haskey(spargs, :title)
            loc = lowercase(string(spargs[:title_location]))
            field = if loc == "left"
                :_left_title
            elseif loc == "right"
                :_right_title
            else
                :title
            end
            ax[field][:set_text](spargs[:title])
            ax[field][:set_fontsize](spargs[:titlefont].pointsize)
            ax[field][:set_color](getPyPlotColor(spargs[:titlefont].color))
            ax[:set_title](spargs[:title], loc = loc)
            # TODO: set other font attributes
        end

        # axes = [ax]
        # # handle right y axis
        # axes = [getLeftAxis(figorax)]
        # if usingRightAxis(plt)
        #     push!(axes, getRightAxis(figorax))
        #     if get(spargs, :yrightlabel, "") != ""
        #         rightax = getRightAxis(figorax)
        #         rightax[:set_ylabel](spargs[:yrightlabel])
        #     end
        # end

        for letter in (:x, :y, :z)
            axissym = symbol(letter, :axis)
            axis = spargs[axissym]
            # @show axis
            # DD(axis.spargs, "updateplot")
            # @show haskey(ax, axissym)
            haskey(ax, axissym) || continue
            applyPyPlotScale(ax, axis[:scale], letter)
            addPyPlotLims(ax, axis[:lims], letter)
            addPyPlotTicks(ax, get_ticks(axis), letter)
            ax[symbol("set_", letter, "label")](axis[:guide])
            if get(axis.d, :flip, false)
                ax[symbol("invert_", letter, "axis")]()
            end
            # for tmpax in axes
                tmpax = ax
                tmpax[axissym][:label][:set_fontsize](axis[:guidefont].pointsize)
                for lab in tmpax[symbol("get_", letter, "ticklabels")]()
                    lab[:set_fontsize](axis[:tickfont].pointsize)
                    lab[:set_rotation](axis[:rotation])
                end
                if get(spargs, :grid, false)
                    fgcolor = getPyPlotColor(spargs[:foreground_color_grid])
                    tmpax[axissym][:grid](true, color = fgcolor)
                    tmpax[:set_axisbelow](true)
                end
            # end
            # @show ""
        end


        # # handle each axis in turn
        # for letter in ("x", "y", "z")
        #     axis, scale, lims, ticks, flip, lab, rotation =
        #         axis_symbols(letter, "axis", "scale", "lims", "ticks", "flip", "label", "rotation")
        #     haskey(ax, axis) || continue
        #     haskey(spargs, scale) && applyPyPlotScale(ax, spargs[scale], letter)
        #     haskey(spargs, lims)  && addPyPlotLims(ax, spargs[lims], letter)
        #     haskey(spargs, ticks) && addPyPlotTicks(ax, spargs[ticks], letter)
        #     haskey(spargs, lab)   && ax[symbol("set_", letter, "label")](spargs[lab])
        #     if get(spargs, flip, false)
        #         ax[symbol("invert_", letter, "axis")]()
        #     end
        #     for tmpax in axes
        #         tmpax[axis][:label][:set_fontsize](guidesz)
        #         for lab in tmpax[symbol("get_", letter, "ticklabels")]()
        #             lab[:set_fontsize](ticksz)
        #             haskey(spargs, rotation) && lab[:set_rotation](spargs[rotation])
        #         end
        #         if get(spargs, :grid, false)
        #             fgcolor = getPyPlotColor(plt.plotargs[:foreground_color_grid])
        #             tmpax[axis][:grid](true, color = fgcolor)
        #             tmpax[:set_axisbelow](true)
        #         end
        #     end
        # end

        # do we want to change the aspect ratio?
        aratio = get(spargs, :aspect_ratio, :none)
        if aratio != :none
            ax[:set_aspect](isa(aratio, Symbol) ? string(aratio) : aratio, anchor = "C")
        end
    end
end


# -----------------------------------------------------------------

# TODO: these should apply to a Subplot, NOT a Plot

# function createPyPlotAnnotationObject(plt::Plot{PyPlotBackend}, x, y, val::@compat(AbstractString))
#     ax = getLeftAxis(plt)
#     ax[:annotate](val, xy = (x,y))
# end
#
#
# function createPyPlotAnnotationObject(plt::Plot{PyPlotBackend}, x, y, val::PlotText)
#     ax = getLeftAxis(plt)
#     ax[:annotate](val.str,
#         xy = (x,y),
#         family = val.font.family,
#         color = getPyPlotColor(val.font.color),
#         horizontalalignment = val.font.halign == :hcenter ? "center" : string(val.font.halign),
#         verticalalignment = val.font.valign == :vcenter ? "center" : string(val.font.valign),
#         rotation = val.font.rotation * 180 / π,
#         size = val.font.pointsize
#     )
# end
#
# function _add_annotations{X,Y,V}(plt::Plot{PyPlotBackend}, anns::AVec{@compat(Tuple{X,Y,V})})
#     for ann in anns
#         createPyPlotAnnotationObject(plt, ann...)
#     end
# end

# -----------------------------------------------------------------

# function _create_subplot(subplt::Subplot{PyPlotBackend}, isbefore::Bool)
#     l = subplt.layout
#     plotargs = getplotargs(subplt, 1)
#     fig = pyplot_figure(plotargs)
#
#     nr = nrows(l)
#     for (i,(r,c)) in enumerate(l)
#         # add the plot to the figure
#         nc = ncols(l, r)
#         fakeidx = (r-1) * nc + c
#         ax = fig[:add_subplot](nr, nc, fakeidx)
#
#         subplt.plts[i].o = PyPlotAxisWrapper(ax, nothing, fig, [])
#         pyplot_3d_setup!(subplt.plts[i].o, plotargs)
#     end
#
#     subplt.o = PyPlotAxisWrapper(nothing, nothing, fig, [])
#     pyplot_3d_setup!(subplt.o, plotargs)
#     true
# end
#
# # this will be called internally, when creating a subplot from existing plots
# # NOTE: if I ever need to "Rebuild a "ubplot from individual Plot's"... this is what I should use!
# function subplot(plts::AVec{Plot{PyPlotBackend}}, layout::AbstractLayout, d::KW)
#     validateSubplotSupported()
#
#     p = length(layout)
#     n = sum([plt.n for plt in plts])
#
#     pkg = PyPlotBackend()
#     newplts = Plot{PyPlotBackend}[begin
#         plt.plotargs[:subplot] = true
#         _create_plot(pkg, plt.plotargs)
#     end for plt in plts]
#
#     subplt = Subplot(nothing, newplts, PyPlotBackend(), p, n, layout, d, true, false, false, (r,c) -> (nothing,nothing))
#
#     _preprocess_subplot(subplt, d)
#     _create_subplot(subplt, true)
#
#     for (i,plt) in enumerate(plts)
#         for seriesargs in plt.seriesargs
#             _add_series_subplot(newplts[i], seriesargs)
#         end
#     end
#
#     _postprocess_subplot(subplt, d)
#
#     subplt
# end


function _remove_axis(plt::Plot{PyPlotBackend}, isx::Bool)
    if isx
        plot!(plt, xticks=zeros(0), xlabel="")
    else
        plot!(plt, yticks=zeros(0), ylabel="")
    end
end

function _expand_limits(lims, plt::Plot{PyPlotBackend}, isx::Bool)
    pltlims = plt.o.ax[isx ? :get_xbound : :get_ybound]()
    _expand_limits(lims, pltlims)
end

# -----------------------------------------------------------------

const _pyplot_legend_pos = KW(
    :right => "right",
    :left => "center left",
    :top => "upper center",
    :bottom => "lower center",
    :bottomleft => "lower left",
    :bottomright => "lower right",
    :topright => "upper right",
    :topleft => "upper left"
  )

# function addPyPlotLegend(plt::Plot)
# function addPyPlotLegend(plt::Plot, ax)
function addPyPlotLegend(plt::Plot, sp::Subplot, ax)
    leg = sp.attr[:legend]
    if leg != :none
        # gotta do this to ensure both axes are included
        labels = []
        handles = []
        for series in plt.series_list
            if get_subplot(series) === sp &&
                        series.d[:label] != "" &&
                        !(series.d[:seriestype] in (
                            :hist,:density,:hexbin,:hist2d,:hline,:vline,
                            :contour,:contour3d,:surface,:wireframe,
                            :heatmap,:path3d,:scatter3d, :pie, :image))
                push!(handles, series.d[:serieshandle][1])
                push!(labels, series.d[:label])
            end
        end
        # args = filter(x -> !(x.d[:seriestype] in (
        #     :hist,:density,:hexbin,:hist2d,:hline,:vline,
        #     :contour,:contour3d,:surface,:wireframe,
        #     :heatmap,:path3d,:scatter3d, :pie, :image
        # )), plt.series_list)
        # args = filter(x -> x[:label] != "", args)
        # if length(args) > 0
        if !isempty(handles)
            leg = ax[:legend](handles,  #[d[:serieshandle][1] for d in args],
                labels, #[d[:label] for d in args],
                loc = get(_pyplot_legend_pos, leg, "best"),
                scatterpoints = 1,
                fontsize = sp.attr[:legendfont].pointsize
                # framealpha = 0.6
            )
            leg[:set_zorder](1000)

            fgcolor = getPyPlotColor(sp.attr[:foreground_color_legend])
            for txt in leg[:get_texts]()
                PyPlot.plt[:setp](txt, color = fgcolor)
            end

            # set some legend properties
            frame = leg[:get_frame]()
            frame[:set_facecolor](getPyPlotColor(sp.attr[:background_color_legend]))
            frame[:set_edgecolor](fgcolor)
        end
    end
end

# -----------------------------------------------------------------

function finalizePlot(plt::Plot{PyPlotBackend})
    for sp in plt.subplots
        # ax = getLeftAxis(plt)
        ax = getAxis(sp)
        addPyPlotLegend(plt, sp, ax)
        for asym in (:xaxis, :yaxis, :zaxis)
            updateAxisColors(ax, sp.attr[asym])
        end
    end
    drawfig(plt.o)
    plt.layout.bbox = py_bbox_fig(plt)
    update_child_bboxes!(plt.layout)
    update_position!(plt.layout)
    PyPlot.draw()
end

# function finalizePlot(subplt::Subplot{PyPlotBackend})
#     fig = subplt.o.fig
#     for (i,plt) in enumerate(subplt.plts)
#         ax = getLeftAxis(plt)
#         addPyPlotLegend(plt, ax)
#         updateAxisColors(ax, plt.plotargs)
#     end
#     # fig[:tight_layout]()
#     PyPlot.draw()
# end


# -----------------------------------------------------------------

# NOTE: to bring up a GUI window in IJulia, need some extra steps
function Base.display(::PlotsDisplay, plt::AbstractPlot{PyPlotBackend})
    finalizePlot(plt)
    if isa(Base.Multimedia.displays[end], Base.REPL.REPLDisplay)
        display(getfig(plt.o))
    else
        # # PyPlot.ion()
        # PyPlot.figure(getfig(plt.o).o[:number])
        # PyPlot.draw_if_interactive()
        # # PyPlot.ioff()
    end
    # PyPlot.plt[:show](block=false)
    getfig(plt.o)[:show]()
end


const _pyplot_mimeformats = Dict(
    "application/eps"         => "eps",
    "image/eps"               => "eps",
    "application/pdf"         => "pdf",
    "image/png"               => "png",
    "application/postscript"  => "ps",
    "image/svg+xml"           => "svg"
)


for (mime, fmt) in _pyplot_mimeformats
    @eval function Base.writemime(io::IO, ::MIME{symbol($mime)}, plt::AbstractPlot{PyPlotBackend})
        finalizePlot(plt)
        fig = getfig(plt.o)
        fig.o["canvas"][:print_figure](
            io,
            format=$fmt,
            # bbox_inches = "tight",
            # figsize = map(px2inch, plt.plotargs[:size]),
            facecolor = fig.o["get_facecolor"](),
            edgecolor = "none",
            dpi = DPI
        )
    end
end
