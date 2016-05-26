import numpy as np
from pylab import *
import decimal
data = np.loadtxt('output_r_0.05_matterpower.dat')
data =data.T
import math


x = data[0][0:]
y = data[1][0:]
area = 0
# calculates the mean correalation function
for j in range(len(y)-1):
	area =area + ((sin((x[j]+x[j+1])/2.))**6)/((x[j]+x[j+1])/2.)**4*(y[j+1]+y[j])/2. * (x[j+1]-x[j])


V = 150.**3
w = area/(2*pi**2*V**2)
l = np.arange(0.000001,0.000006,0.000001)#,0.000001)
print(l[0])
for n in l:
	print(n)
	x = n*V
	nodata = 100
	P = np.zeros(nodata)
	k = np.arange(nodata)
# calculates the probability of finding N clusters in a cubic volume V
	for N in k:
		P[N] = (x**N*(exp(-x))*(1. - 0.5*x**2*w*((N-N**2)/x**2 + 2*N/x - 1.)))/((math.factorial(N)))
#	print(k,P);quit()
	plot(k,P)
	
        #xscale('log')
	#yscale('log')


show()

