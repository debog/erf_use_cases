# Module for functions related to reading data from ERF plt files

import os
import yt
import numpy as np
import glob

# given the prefix and index, generate the plt filename (as written by ERF)
def get_fname(prefix, index):
    fname = "{:s}{:05d}".format(prefix,int(index))
    return fname

# returns a list of plt filenames in the specified directory as an array of strings
def get_plt_list(path):
    try:
        pathname = os.path.join(path, 'plt*')
        filenames = glob.glob(pathname)
        return filenames
    except FileNotFoundError:
        return []

# get the field (variable) names in a given plt file
def get_field_names(fname):
    yt.set_log_level("error")
    ds = yt.load(fname)
    names = []
    for (_,name) in ds.field_list:
        names.append(name)
    return names

# get the grid field (variable) names in a given plt file
def get_grid_field_names(fname):
    names_all = get_field_names(fname)
    names = []
    for name in names_all:
        if (not name.startswith("particle_")):
            names.append(name)
    return names

# get the particle field (variable) names in a given plt file
def get_particle_field_names(fname):
    yt.set_log_level("error")
    ds = yt.load(fname)
    names = []
    for (_,name) in ds.field_list:
        if name.startswith("particle_"):
            names.append(name)
    return names

# get the data for a given Eulerian variable name as a numpy array
def get_data_array(cg, name):
    return np.array(cg[('boxlib', name)][:, :, :])

# get the data for a given particle species and attribute as a numpy array
def get_particle_var_array(cg, pcname, name):
    return np.array(cg[(pcname, name)])

# read a plt file for the specified variable names
def read_plt(fname, varnames):
    print('Reading grid data from ', fname, '...')
    yt.set_log_level("error")
    ds = yt.load(fname)
    cg = ds.covering_grid(0, ds.domain_left_edge, ds.domain_dimensions, fields=varnames)
    time = np.array(ds.current_time).flatten()[0]
    for dataset in varnames:
        cg[('boxlib', dataset)]

    return ds, cg, time

# read a plt file for the specified particle species and attributes
def read_plt_particles(fname, pcname, varnames):
    print('Reading particle data from ', fname, '...')
    yt.set_log_level("error")
    ds = yt.load(fname)
    cg = ds.covering_grid(0, ds.domain_left_edge, ds.domain_dimensions, fields=varnames)
    time = np.array(ds.current_time).flatten()[0]
    for dataset in varnames:
        cg[(pcname, dataset)]

    return ds, cg, time
