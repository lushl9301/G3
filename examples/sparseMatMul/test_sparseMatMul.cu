// ----------------------------------------------------------------
// Gunrock -- Fast and Efficient GPU Graph Library
// ----------------------------------------------------------------
// This source code is distributed under the terms of LICENSE.TXT
// in the root directory of this source distribution.
// ----------------------------------------------------------------

/**
 * @file
 * test_pr.cu
 *
 * @brief Simple test driver program for PageRank.
 */

#include <gunrock/app/sparseMatMul/sparseMatMul_app.cu>
#include <gunrock/app/test_base.cuh>
#include <cstdio>
#include <iostream>

using namespace gunrock;

/******************************************************************************
 * Main
 ******************************************************************************/

/**
 * @brief Enclosure to the main function
 */
struct main_struct {
  void readFeature(std::ifstream& svmlight_file, int* row_offsets, int* col_offsets, double* val,
                   int& dim, int& n_rows, int& nnz) {
    n_rows = 0, nnz = 0;
    std::vector<int> indptr, indices;
    std::vector<double> feature_val;
    indptr.push_back(0);

    int max_idx = 0, max_label = 0;
    while(true) {
      std::string line;
      getline(svmlight_file, line);
      if (svmlight_file.eof()) break;
      indptr.push_back(indptr.back());
      std::istringstream ss(line);

      int label = -1;
      ss >> label;
//      labels.push_back(label);
      if (ss.fail()) continue;
      max_label = std::max(max_label, label);

      while (true) {
        std::string kv;
        ss >> kv;
        if(ss.fail()) break;
        std::istringstream kv_ss(kv);

        int k;
        float v;
        char col;
        kv_ss >> k >> col >> v;

        feature_val.push_back(v);
        indices.push_back(k);
        indptr.back() += 1;
        max_idx = std::max(max_idx, k);
      }
    }
    row_offsets = indptr.data();
    col_offsets = indices.data();
    val = feature_val.data();
    n_rows = indptr.size() - 1;
    nnz = indices.size();
    dim = max_idx + 1;
//    gcnParams->output_dim = max_label + 1;
  }

  /**
   * @brief the actual main function, after type switching
   * @tparam VertexT    Type of vertex identifier
   * @tparam SizeT      Type of graph size, i.e. type of edge identifier
   * @tparam ValueT     Type of edge values
   * @param  parameters Command line parameters
   * @param  v,s,val    Place holders for type deduction
   * \return cudaError_t error message(s), if any
   */
  template <typename VertexT,  // Use int as the vertex identifier
            typename SizeT,    // Use int as the graph size type
            typename ValueT>   // Use int as the value type
  cudaError_t
  operator()(util::Parameters &parameters, VertexT v, SizeT s, ValueT val) {
    typedef typename app::TestGraph<VertexT, SizeT, ValueT, graph::HAS_CSR>
        GraphT;
    // typedef typename GraphT::CooT CooT;

    cudaError_t retval = cudaSuccess;
    bool quick = parameters.Get<bool>("quick");
    bool quiet = parameters.Get<bool>("quiet");

    util::CpuTimer cpu_timer;
    GraphT graph;

    cpu_timer.Start();
    GUARD_CU(graphio::LoadGraph(parameters, graph));
    cpu_timer.Stop();
    parameters.Set("load-time", cpu_timer.ElapsedMillis());

    std::ifstream featurefile(parameters.Get<std::string>("inx"), std::ifstream::in),
    weightfile(parameters.Get<std::string>("inw"), std::ifstream::in);
    int *row_offsets, *col_offsets, dim, nnz, n_rows;
    int hidden_dim = parameters.Get<int>("hidden_dim");
    double *vals, *b, *c;
    readFeature(featurefile, row_offsets, col_offsets, vals, dim, n_rows, nnz);

    b = new double[dim * hidden_dim];
    for (int i = 0; i < dim * hidden_dim; i++) weightfile >> b[i];

    c = new double[dim * hidden_dim];
    sparseMatMul(n_rows, nnz, row_offsets, col_offsets, vals, dim, hidden_dim, b, c);
    for (int i = 0; i < graph.nodes; i++) {
      for (int j = 0; j < dim; j++) std::cout << c[i] * hidden_dim + j << ' ';
      std::cout << std::endl;
    }
    return retval;
  }
};

int main(int argc, char **argv) {
  cudaError_t retval = cudaSuccess;
  util::Parameters parameters("test graphsum");
  GUARD_CU(graphio::UseParameters(parameters));
  GUARD_CU(app::sparseMatMul::UseParameters(parameters));
  GUARD_CU(app::UseParameters_test(parameters));
  GUARD_CU(parameters.Parse_CommandLine(argc, argv));
  if (parameters.Get<bool>("help")) {
    parameters.Print_Help();
    return cudaSuccess;
  }
  GUARD_CU(parameters.Check_Required());

  return app::Switch_Types<app::VERTEXT_U32B |  // app::VERTEXT_U64B |
                           app::SIZET_U32B |    // app::SIZET_U64B |
                           app::VALUET_F64B |   // app::VALUET_F64B |
                           app::DIRECTED | app::UNDIRECTED>(parameters,
                                                            main_struct());
}

// Leave this at the end of the file
// Local Variables:
// mode:c++
// c-file-style: "NVIDIA"
// End:
