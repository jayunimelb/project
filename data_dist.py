import numpy as np
from astropy.io import fits

list = fits.open('/Users/sanjaykumarp/Downloads/2500d_cluster_sample_fiducial_cosmology.fits')
#print(list.info())
print(list[1].data[0])