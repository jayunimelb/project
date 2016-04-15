import numpy as np
from pylab import *
#import matplotlib.pyplot as *                                                                                                                                          
data = np.loadtxt('output_r_0.05_matterpower.dat')
data =data.T


x = data[0][0:]
y = data[1][0:]
area = 0
for j in range(len(y)-1):
	area =area + (sin((x[j]+x[j+1])/2.)**2/((x[j]+x[j+1])/2.)**2)*((y[j+1]+y[j])/2.) * (x[j+1]-x[j])

print area


quit()
#show()
