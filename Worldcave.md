# Worldcave

NOTE: This may be a mod description for spline_caves.lua if I make a mod out of
it.

This mod adds a cave which goes through the whole world.
The cave follows a single long spline curve, so it has no branches.


### How it works

The main part of the algorithm is the procedural calculation of a distance
field
which determines the distances to the cave centre for all integer positions
inside a cuboid given by the user (e.g. given by `minp` and `maxp` for mapgen).
It can be summarised as follows:
* From a global perspective, the whole world is divided into a coarse cartesian
  grid.
  The grid cells are ordered along a 3D Pseudo Hilbert Curve.
  The program performs this ordering procedurally, i.e. it does not calculate
  a big Pseudo Hilbert Curve table at once but instead, for a given grid cell,
  it calculates the directions to the next and previous cells.
* For a cuboid **Cub** given by the user,
  determine all grid cells containing a part of the cave
  which intersects **Cub**.
  These cells are the hull of cell volumes containing **Cub** plus one
  additional slice of cells in each direction.
* For each of these grid cells, calculate a point set for the curve which
  corresponds to the centre of the cave:
  * For the current grid cell, Pseudo-randomly select basis points for a basis
    spline curve
    * The points are positioned on the surface of a cube corresponding to 3x3x3
      grid cells where the current cell is the center of this cube.
      TODO: configurable to be inside and not on surface
    * Since the points are basis points, the corresponding curve stays inside
      the volume of the 3x3x3 cells.
      To avoid that the corresponding cave can go a bit outside of this volume
      because of its cave thickness, the cube is shrunk by this thickness.
    * The PRNG for the point selection is seeded with the cell position.
    * The reasons for choosing points in this way are as follows:
      * Since the points are on the border of the 3x3x3 block of grid cells
        minus the cave thickness
        instead of the border of, for example, only the current cell,
        the Pseudo Hilbert Curve ordering is hidden from the player.
      * Selecting the points only on the border and not from within a cube
        increases the distances between successive basis points on average,
        which leads to a longer and more straight-looking cave.
      * Due to the PRNG seeding, the same curve appears if the algorithm is
        executed multiple times for the same grid cells.
        This is necessary for a procedural cave generation.
  * For the current grid cell, connect the spline curve to the curves
    of its predecessor and successor along the Hilbert Curve ordering
  * Sample the current grid cell's curve, i.e. convert it to a point set.
    This is a perforance-critical part of the program.
    The points are calculated so that the L2 distance between two successive
    points on the curve is within [0.5, 1.1].
* Unify the point sets and then remove all points which are outside the cuboid
  **Cub** plus the cave thickness.
  If no points are left, there is no cave in **Cub** and the program aborts.
* Calculate a distance field for these points.
  The distance field is an array that contains the closest distance to any of
  the points from all integer positions within **Cub**.
  For performance, the calculated distances are at most `max_dist`,
  which is a value at least as big as the cave thickness.
  Calculating a L2 distance field would be computationally too expensive,
  and a Manhattan or Maximum distance field would lead to somewhat ugly caves.
  Therefore, the program approximates the L2 distance with the Manhattan
  distance and a rotated Manhatten distance.
  This approximation may be even better suited than the L2 distance for the
  caves.
  * Calculate a Manhattan distance field for the points.
    The algorithm for this is analogous to Minetest's light spread algorithm.
    The size of the distance field is larger than **Cub** to
    incorporate cave thickness.
    * Initialize a distance field array and set each value to `max_dist`
    * Add each point from the point set to this distance field:
      * Discretize its coordinates
      * If it's inside the distance field, follow the next step, and otherwise
        skip this point
      * Set the distance field entry for this discrete position to `0`
      * Add this distance field entry to a queue
     * Repeatedly iterate over the queue to spread distances to their six
       neighbours, analogous to Minetest's light spreading.
       For performance, spreading stops if a distance exceeds `max_dist`.
  * Calculate a rotated Manhattan distance field for the points.
    * Rotate the points by 45 degrees around X and then by 45 degrees around Z
    * Calculate a Manhattan distance field for the rotated points with the same
      algorithm as explained before.
      The size of this distance field is the hull cuboid of the rotated points
      plus the cave thickness.
  * Merge the two distance fields into a new one which corresponds to the cuboid
    **Cub**.
    For each point of the new distance field:
    * Get the distance from the Manhattan distance field at this point
    * Rotate the point, discretize it, and then get the distance from the
      rotated Manhattan distance field at this point
    * Set the entry of the new distance field to the maximum of the two
      distances

To generate caves, the algorithm uses the distance field calculation together
with the Weierstraß function.
The Weierstraß function is used to generate rough cave walls.
* Calculate the distance field for `minp` and `maxp`, which determine the cuboid
  where map should be generated
* For each integer point in this cuboid, set air if it is in a cave:
  * Use the Weierstraß function three times: for arguments `(2, x)`, `(3, y)`
    and `(5, z)`.
    For performance, weak tables are used to cache function evaluations.
  * Combine the three values to a number `o(x,y,z)` in `[0, 1]`
  * Set air if `d(x,y,z) <= c1 + (c2 - c1) * o(x,y,z)` holds,
    where `c1` and `c2` are the minimum and maximum cave thickness respectively
    and `d` is the distance field.

