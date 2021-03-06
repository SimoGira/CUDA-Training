////////////////////////////////////////////////////////////////////////////
//
//
//  EXAMPLE OF TILED 2D PATTERN CONVOLUTION CHAPTER 7
//
//
////////////////////////////////////////////////////////////////////////////

// includes CUDA
#include "cuda_runtime.h"
#include "device_launch_parameters.h"

// includes, system
#include <stdlib.h>
#include <stdio.h>
#include <math.h>
#include <cuda.h>


#define MASK_WIDTH 5
#define CHECK_ERROR(call) { \
    cudaError_t err = call; \
    if (err != cudaSuccess) { \
        printf("%s in %s at line %d\n", cudaGetErrorString(err), __FILE__, __LINE__); \
        exit(err); \
    } \
}

void printMatrix(float *A, int height, int width) {
	for (int i = 0; i < height; i++) {
		for (int j = 0; j < width; j++)
		{
			printf("%.2f ", A[i*height + j]);
		}
		printf("\n");
	}
	printf("\n");
}

// compute vector convoluiton
// each thread performs one pair-wise convolution
////////////////////////////////////////////////////////////////////////////////
//! Simple matrix convolution kernel
//! @param d_N  input data in global memory
//! @param d_M  input mask data in global memory
//! @param d_P  output data in global memory
//! @param height  number of rows of the input matrix N
//! @param widht  number of cols of the input matrix N
////////////////////////////////////////////////////////////////////////////////

__global__
void convolution_2D_basic_kernel(float *N, float *M, float *P, int height, int width) {

	int Row = blockIdx.y * blockDim.y + threadIdx.y;
	int Col = blockIdx.x * blockDim.x + threadIdx.x;

	if (Row < height && Col < width) {

		int y = Row - (MASK_WIDTH) / 2;
		int x = Col - (MASK_WIDTH) / 2;
		float Pvalue = 0.0f;

		for (int i = 0; i < MASK_WIDTH; i++) {
			if (y + i >= 0 && y + i < height) {
				for (int j = 0; j < MASK_WIDTH; j++) {
					if (x + j >= 0 && x + j < width) {
						Pvalue += N[(y + i) * width + (x + j)] * M[i * MASK_WIDTH + j];
					}
				}
			}
		}
		P[Row * width + Col] = Pvalue;
	}
}

////////////////////////////////////////////////////////////////////////////////
//! Run a simple matrix convolution for CUDA
////////////////////////////////////////////////////////////////////////////////

float convolution_2D_basic(float *h_N, float h_M[MASK_WIDTH][MASK_WIDTH], float *h_P, int height, int width) {

	float *d_N, *d_M, *d_P;
	int size = height * width * sizeof(float);
	int sizeMask_Width = MASK_WIDTH * MASK_WIDTH * sizeof(float);

	cudaEvent_t startTimeCuda, stopTimeCuda;
	cudaEventCreate(&startTimeCuda);
	cudaEventCreate(&stopTimeCuda);

	//1. Allocate global memory on the device for N, M and P
	CHECK_ERROR(cudaMalloc((void**)&d_N, size));
	CHECK_ERROR(cudaMalloc((void**)&d_P, size));
	CHECK_ERROR(cudaMalloc((void**)&d_M, sizeMask_Width));

	// copy N and M to device memory
	cudaMemcpy(d_N, h_N, size, cudaMemcpyHostToDevice);
	cudaMemcpy(d_M, h_M, sizeMask_Width, cudaMemcpyHostToDevice);

	//2. Kernel launch code - to have the device to perform the actual convolution
	// ------------------- CUDA COMPUTATION ---------------------------
	dim3 dimGrid(ceil(width / 4.0), ceil(height / 4.0), 1);
	dim3 dimBlock(4.0, 4.0, 1);
	cudaEventRecord(startTimeCuda, 0);
	cudaEventSynchronize(startTimeCuda);

	convolution_2D_basic_kernel << <dimGrid, dimBlock >> >(d_N, d_M, d_P, height, width);

	cudaEventRecord(stopTimeCuda, 0);

	// ---------------------- CUDA ENDING -----------------------------
	cudaEventSynchronize(stopTimeCuda);
	float msTime;
	cudaEventElapsedTime(&msTime, startTimeCuda, stopTimeCuda);
	printf("KernelTime: %f\n", msTime);

	//3. copy C from the device memory
	cudaMemcpy(h_P, d_P, size, cudaMemcpyDeviceToHost);

	// // cleanup memory
	cudaFree(d_N);
	cudaFree(d_M);
	cudaFree(d_P);

	return msTime;
}

// Perform 2D convolution on the host
void sequential_2D_Conv(float *h_N, float h_M[MASK_WIDTH][MASK_WIDTH], float *h_PS, int height, int width) {

	for (int i = 0; i < height; i++) {
		for (int j = 0; j < width; j++) {

			int y = i - (MASK_WIDTH) / 2;
			int x = j - (MASK_WIDTH) / 2;

			//printf("y = %d, x = %d\n\n", y, x);
			float Pvalue = 0.0f;

			for (int k = 0; k < MASK_WIDTH; k++) {
				if (y + k >= 0 && y + k < height) {
					for (int t = 0; t < MASK_WIDTH; t++) {
						if (x + t >= 0 && x + t < width) {
							Pvalue += h_N[(y + k)*width + (x + t)] * h_M[k][t];
						}
					}
				}
			}
			h_PS[i*width + j] = Pvalue;
		}
	}
}

////////////////////////////////////////////////////////////////////////////////
// Program main
////////////////////////////////////////////////////////////////////////////////
int main(int argc, char **argv) {
	printf("%s Starting...\n\n", argv[0]);

	float *h_P, *h_N, *h_PS;
	const int rows = 1024;
	const int cols = 1024;
	float msTime, msTime_seq;
	cudaEvent_t startTimeCuda, stopTimeCuda;
	float h_M[MASK_WIDTH][MASK_WIDTH] = {
		{ 1, 2, 3, 2, 1 },
		{ 2, 3, 4, 3, 2 },
		{ 3, 4, 5, 4, 3 },
		{ 2, 3, 4, 3, 2 },
		{ 1, 2, 3, 2, 1 }
	};

	cudaEventCreate(&startTimeCuda);
	cudaEventCreate(&stopTimeCuda);

	// allocate memory for host vectors
	h_N = (float*)malloc(sizeof(float)*rows*cols);     // input array
	h_P = (float*)malloc(sizeof(float)*rows*cols);     // output array
	h_PS = (float*)malloc(sizeof(float)*rows*cols);    // output array sequential result

													   /*
													   *  NB if you use the random numbers you may consider the tollerance error of approximation
													   *  between CPU and GPU
													   *  srand(time(NULL));
													   */
	for (int i = 0; i < rows; i++) {
		for (int j = 0; j < cols; j++)
		{
			h_N[i*rows + j] = (float)((i + j + 1) % 10);
			//h_N[i] = ((float)rand() / (float)(RAND_MAX)) * 100;
		}
	}

	// ---------------------- PARRALLEL CONVOLUTION -------------------------
	msTime = convolution_2D_basic(h_N, h_M, h_P, rows, cols);

	// ---------------------- PERFORM SEQUENTIAL CONVOLUTION ----------------
	cudaEventRecord(startTimeCuda, 0);
	cudaEventSynchronize(startTimeCuda);
	sequential_2D_Conv(h_N, h_M, h_PS, rows, cols);
	cudaEventRecord(stopTimeCuda, 0);
	cudaEventSynchronize(stopTimeCuda);
	cudaEventElapsedTime(&msTime_seq, startTimeCuda, stopTimeCuda);
	printf("HostTime: %f\n", msTime_seq);

	/*
	printf("----------------- INPUT MATRIX -----------------\n");
	printMatrix(h_N, rows, cols);

	printf("---------- MATRIX RESULT - SEQUENTIAL ----------\n");
	printMatrix(h_PS, rows, cols);


	printf("---------- MATRIX RESULT - PARALLEL ------------\n");
	printMatrix(h_P, rows, cols);
	*/


	// check the result
	for (int i = 0; i < rows; i++) {
		for (int j = 0; j < cols; j++) {
			if (h_P[i*rows + j] != h_PS[i*rows + j]) {
				printf("Error into result: h_P[%d] = %.2f != %.2f = h_PS[%d]\n", i*rows + j, h_P[i*rows + j], h_PS[i*rows + j], i*rows + j);
				goto Error;
			}
		}
	}

	printf("Ok convolution completed with success!\n\n");
	printf("Speedup: %f\n", msTime_seq / msTime);

	// cleanup memory
	free(h_N);
	free(h_P);
	free(h_PS);

#ifdef _WIN32
	system("pause");
#endif
	return 0;
	
Error:
	free(h_N);
	free(h_P);
	free(h_PS);
#ifdef _WIN32
	system("pause");
#endif
	return -1;

}
