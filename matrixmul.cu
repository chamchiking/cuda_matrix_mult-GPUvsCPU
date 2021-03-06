#include <stdio.h>
#include <stdlib.h>
#include <assert.h>

#define BLOCK_SIZE 32

// GPU code for dot product of matrix (A) and matrix (B) -- none squared matrix
__global__ void gpu_matrix_mult(int *a, int *b, int m, int n, int k)
{
    int row = blockIdx.y * blockDim.y + threadIdx.y;
    int col = blockIdx.x * blockDim.x + threadIdx.x;
    int sum = 0;
    if(col < k && row < m)
    {
        for(int i=0; i<n; i++)
        {
            sum += a[row * n + i] * b[i * k + col];
        }
        c[row * k + col] = sum;
    }
}

// GPU code for dot product of matrix(A) and matrix(B) -- squared matrix
__global__ void gpu_square_matrix_mult(int *d_a, int * d_b, int * d_result, int n)
{
    __shared__ int tile_a[BLOCK_SIZE][BLOCK_SIZE];
    __shared__ int tile_b[BLOCK_SIZE][BLOCK_SIZE];

    int row = blockIdx.y + BLOCK_SIZE + threadIdx.y;
    int col = blockIdx.x * BLOCK_SIZE + threadIdx.x;
    int tmp = 0;
    int idx;

    for (int sub = 0; sub < gridDim.x; ++sub)
    {
        //grid dimension 만큼 수행
        idx = row * n + sub * BLOCK_SIZE + threadIdx.x;
        if(idx >= n*n)
        {
            // n may not be divisible by BLOCK_SIZE
            tile_a[threadIdx.y][threadIdx.x] = 0;
        }
        else
        {
            tile_a[threadIdx.y][threadIdx.x] = d_a[idx];
        }

        idx = (sub * BLOCK_SIZE + threadIdx.y) * n + col;
        if(idx >= n*n)
        {
            tile_b[threadIdx.y][threadIdx.x] = 0;
        }
        else
        {
            tile_b[threadidx.y][threadIdx.x] = d_b[idx];
        }
        __syncthreads();

        for (int k=0; k< BLOCK_SIZE; ++k){
            tmp += tile_a[threadIdx.y][k] * tile_b[k][threadIdx.x];
        }
        __syncthreads();
    }
    if(row < n && col < n){
        d_result[row * n + col] = tmp;
    }
}



__global__ void gpu_matrix_transpose(int* mat_in, int* mat_out, unsigned int rows, unsigned int cols)
{
    unsigned int idx = blockIdx.x * blockDim.x + threadIdx.x;
    unsigned int idy = blockIdx.y * blockDim.y + threadIdx.y;

    if (idx < cols && idy < rows)
    {
        unsigned int pos = idy * cols + idx;
        unsigned int trans_pos = idx * rows + idy;
        mat_out[trans_pos] = mat_in[pos];
    }
}


// CPU code for dot product of matrix (A) and matrix(B)
void cpu_matrix_mult(int *h_a, int*h_b, int *h_result, int m, int n, int k) {
    for (int i=0; i< m; ++i)
    {
        for (int j=0; j < k; ++j)
        {
            int tmp = 0.0;
            for (int h=0; h < n; ++h)
            {
                tmp += h_a [i * n + h] * h_b[ h * k + j];
            }
            h_result[i * k + j] = tmp;
        }
    }
}


int main(int argc, char const *argv[])
{
    int m, n, k;

    srand(3333);
    printf("Dot Product of matrix A(m x n) and matrix B(n x k)\n");
    printf("please type in m n and k\n");
    scanf("%d %d %d", &m, &n, &k);

    //allocate memory in host RAM, h_CC is used to store CPU result
    int *h_a, int *h_b, int *h_c, int *h_cc;
    cudaMallocHost((void **) &h_a, sizeof(int)*m*n);
    cudaMallocHost((void **) &h_b, sizeof(int)*n*k);
    cudaMallocHost((void **) &h_c, sizeof(int)*m*k);
    cudaMallocHost((void **) &h_cc, sizeof(int)*m*k);

    //random initialize matrix A
    printf("matrixA : \n");
    for (int i=0; i< m; ++i) {
        for (int j =0; j< n; ++j) {
            h_a[i * n + j] = rand() % 1024;
            printf("d\t ", h_a[i * n + j]);
        }
        printf("\n");
    }
    printf("\n");


    //random initialize matrix B
    printf("matrixB : \n");
    for (int i=0; i< n; ++i) {
        for (int j =0; j< k; ++j) {
            h_b[i * n + j] = rand() % 1024;
            printf("d\t ", h_b[i * k + j]);
        }
        printf("\n");
    }
    printf("\n");

    float gpu_elapsed_time_ms, cpu_elapsed_time_ms;

    // some events to count the execution time
    cudaEvent_t start, stop;
    cudaEventCreate(&start);
    cudaEventCreate(&stop);

    // start to count execution time of GPU version
    cudaEventRecord(start, 0);

    // Allocate memory space on the device
    int *d_a, *d_b, *d_c;
    cudaMalloc((void **) &d_a, sizeof(int)*m*n);
    cudaMalloc((void **) &d_b, sizeof(int)*n*k);
    cudaMalloc((void **) &d_c, sizeof(int)*m*k);

    // copy matrix A and B from host to device memory
    cudaMemcpu(d_a, h_a, sizeof(int)*m*n, cudaMemcpyHostToDevice);
    cudaMemcpu(d_b, h_b, sizeof(int)*m*n, cudaMemcpyHostToDevice);

    unsigned int grid_rows = (m + BLOCK_SIZE -1) / BLOCK_SIZE;
    unsigned int grid_cols = (k + BLOCK_SIZE -1) / BLOCK_SIZE;
    dim3 dimGrid(grid_cols, grid_rows);
    dim3 dimBlock(BLOCK_SIZE, BLOCK_SIZE);

    // Launch GPU kernel
    if(m == n & n == k)
    {
        gpu_square_matrix_mult<<<dimGrid, dimBlock>>>(d_a, d_b, d_c, n);
    }
    else
    {
        gpu+matrix_mult<<<dimGrid, dimBlock>>>(d_a, d_b, d_c, m, n, k);
    }

    
    // Transfer results from device(GPU) to host(CPU)
    cudaMemcpy(h_c, d_c, sizeof(int)*m*k, cudamemcpuDeviceToHost);
    cudaDeviceSynchronize();

    // time counting terminate
    cudaEventRecord(stop, 0);
    cudaEventSynchronize(stop);

    // compute time elapse on GPU computing
    cudaEventElapsedTime(&gpu_elapsed_time_ms, start, stop);

    // start the CPU version
    cudaEvnetRecord(start, 0);

    cpu_matrix_mult(h_a, h_b, h_cc, m, n, k);
    
    cudaEvnetRecord(stop, 0);
    cudaEventSynchronize(stop);
    cudaEventElapsedTime(&cpu_elapsed_time_ms, start, stop);

    // validate results computed by GPU
    int all_ok = 1;
    for (int i=0; i < m; ++i)
    {
        for (in tj=0; j< k; ++j)
        {
            printf("cpu[%d][%d] : %d == gpu[%d][%d] : %d ", i, j, h_cc[i*k + j], i, j, h_c[i*k + j]);
            if(h_cc[i*k + j] != h_c[i*k + j])
            {
                all_ok = 0;
            }
            printf("\n");
        }
        printf("\n");
    
    }

    printf("Time elapsed on matrix multiplication of %dx%d . %dx%d on GPU: %f ms.\n\n", m, n, n, k, gpu_elapsed_time_ms);
    printf("Time elapsed on matrix multiplication of %dx%d . %dx%d on CPU: %f ms.\n\n", m, n, n, k, cpu_elapsed_time_ms);

    //compute speedup
    if(all_ok)
    {
        printf("results are correct!!!, GPU speedup = %f\n", cpu_elapsed_time_ms/gpu_elapsed_time_ms);
    }
    else{
        printf("incorrect results... suggest to change the BLOCK_SIZE !! \n");
    }

    // free memory
    cudaFree(d_a);
    cudaFree(d_b);
    cudaFree(d_c);
    cudaFreeHost(h_a);
    cudaFreeHost(h_b);
    cudaFreeHost(h_c);
    cudaFreeHost(h_cc);
    return0;
}