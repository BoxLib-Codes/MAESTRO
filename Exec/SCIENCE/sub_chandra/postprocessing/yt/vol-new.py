#!/usr/bin/env python

import matplotlib
matplotlib.use('agg')

import sys

import yt
import numpy as np
from yt.visualization.volume_rendering.api import \
    Scene, \
    VolumeSource


# this is for the wdconvect problem

def doit(plotfile):

    ds = yt.load(plotfile)
    ds.periodicity = (True, True, True)

    field = ('boxlib', 'radial_velocity')
    ds._get_field_info(field).take_log = False
        
    sc = Scene()


    # add a volume: select a sphere
    #center = (0, 0, 0)
    #R = (5.e8, 'cm')

    #dd = ds.sphere(center, R)

    vol = VolumeSource(ds, field=field)
    vol.use_ghost_zones = True

    sc.add_source(vol)


    # transfer function
    vals = [-5.e6, -2.5e6, -1.25e6, 1.25e6, 2.5e6, 5.e6]
    sigma = 3.e5

    tf =  yt.ColorTransferFunction((min(vals), max(vals)))

    tf.clear()
    cm = "coolwarm"
    for v in vals:
        tf.sample_colormap(v, sigma**2, colormap=cm) #, alpha=0.2)

    sc.get_source(0).transfer_function = tf

    cam = sc.add_camera(ds, lens_type="perspective")        
    cam.resolution = (1080, 1080)
    cam.position = 1.0*ds.domain_right_edge
    
    # look toward the center -- we set this depending on whether the plotfile
    # indicates it was an octant
    try: octant = ds.parameters["octant"]
    except: octant = True

    if octant:
        center = ds.domain_left_edge
    else:
        center = 0.5*(ds.domain_left_edge + ds.domain_right_edge)

    # unit vector connecting center and camera
    normal = (center - cam.position)
    normal /= np.sqrt(normal.dot(normal))

    cam.switch_orientation(normal_vector=normal,
                           north_vector=[0., 0., 1.])
    cam.set_width(ds.domain_width)

    #sc.annotate_axes(alpha=0.05)
    #sc.annotate_domain(ds, color=np.array([0.05, 0.05, 0.05, 0.05]))
    #sc.annotate_grids(ds, alpha=0.05)

    sc.render()
    sc.save("{}_radvel".format(plotfile), sigma_clip=6.0)
    sc.save_annotated("{}_radvel_annotated.png".format(plotfile), 
                      text_annotate=[[(0.05, 0.05), 
                                      "t = {}".format(ds.current_time.d),
                                      dict(horizontalalignment="left")],
                                     [(0.5,0.95), 
                                      "Maestro simulation of He convection on a white dwarf",
                                      dict(color="y", fontsize="24",
                                           horizontalalignment="center")]])

if __name__ == "__main__":

    # Choose a field
    plotfile = ""


    try: plotfile = sys.argv[1]
    except: sys.exit("ERROR: no plotfile specified")

    doit(plotfile)


        
