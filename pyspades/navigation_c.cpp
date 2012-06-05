#include <iostream>
#include <fstream>
#include <string.h>
#include <time.h>

#include <algorithm>
#include <cassert>
#include <deque>

#include "navigation_c.h"

#define get_pos_2d(x, y) ((x) + (y) * MAP_Y)
#define sgn(x) ((x) > 0) - ((x) < 0)

using std::min;
using std::max;

Node* find_node(NavGraph const* graph, int x, int y, int z)
{
    node_map::const_iterator iter = graph->nodes.find(get_pos_2d(x, y));
    if (iter == graph->nodes.end())
        return NULL;
    Node* n = iter->second;
    Node* n_up = n->next[1][1];
    while (n_up != NULL && n_up->z >= z) {
        n = n_up;
        n_up = n->next[1][1];
    }
    return n;
}

int get_potential_node_height(MapData const* map, int x, int y, int z)
{
    int pos = get_pos(x, y, z);
    int height = 0;
    do {
        if (map->geometry[pos])
            break;
        ++height;
        pos -= MAP_X * MAP_Y;
    } while (pos >= 0);
    return height;
}

void try_link_nodes(MapData const* map, node_map& nodes, Node* a, int au, int av)
{
    int const x = a->x + au - 1;
    int const y = a->y + av - 1;
    if (x < 0 || x >= MAP_X || y < 0 || y >= MAP_Y)
        return;
    if (au != 1 && av != 1 &&
        (is_wall(map, a->x + abs(au-1) - 1, a->y + av - 1, a->z) ||
        is_wall(map, a->x + au - 1, a->y + abs(av-1) - 1, a->z)))
        // the target tile is diagonal from our origin tile and two walls block
        // movement in that direction
        return;
    node_map::const_iterator iter = nodes.find(get_pos_2d(x, y));
    if (iter == nodes.end())
        return;
    
    Node* b = iter->second;
    int const bu = 2 - au;
    int const bv = 2 - av;
    do {
        int const diff = abs(a->z - b->z);
        if (diff == 0) {
            a->next[au][av] = b;
            b->next[bu][bv] = a;
            continue;
        }
        if (diff > MAX_FALL)
            continue;
        if ((a->z < b->z && b->height < diff + PLAYER_HEIGHT) ||
            (a->z > b->z && a->height < diff + PLAYER_HEIGHT))
            continue;
        if (diff <= JUMP_HEIGHT) {
            a->next[au][av] = b;
            b->next[bu][bv] = a;
        } else {
            if (a->z < b->z)
                a->next[au][av] = b;
            else
                b->next[bu][bv] = a;
        }
    } while ((b = b->next[1][1]) != NULL);
}

void get_corner_flags(bool corner[3][3], Node const* n)
{
    /* marks special forced neighbor cases */
    if (n->next[1][0]) {
        if (n->next[0][0] && n->next[1][0]->next[0][1] != n->next[0][0])
            corner[1][0] = corner[0][0] = true;
        if (n->next[2][0] && n->next[1][0]->next[2][1] != n->next[2][0])
            corner[1][0] = corner[2][0] = true;
        if (n->next[2][1] &&
            (n->next[1][0]->next[2][2] != n->next[2][1] ||
            n->next[2][1]->next[0][0] != n->next[1][0]))
            corner[1][0] = corner[2][1] = true;
    }
    if (n->next[2][1]) {
        if (n->next[2][0] && n->next[2][1]->next[1][0] != n->next[2][0])
            corner[2][1] = corner[2][0] = true;
        if (n->next[2][2] && n->next[2][1]->next[1][2] != n->next[2][2])
            corner[2][1] = corner[2][2] = true;
        if (n->next[1][2] &&
            (n->next[2][1]->next[0][2] != n->next[1][2] ||
            n->next[1][2]->next[2][0] != n->next[2][1]))
            corner[2][1] = corner[1][2] = true;
    }
    if (n->next[1][2]) {
        if (n->next[2][2] && n->next[1][2]->next[2][1] != n->next[2][2])
            corner[1][2] = corner[2][2] = true;
        if (n->next[0][2] && n->next[1][2]->next[0][1] != n->next[0][2])
            corner[1][2] = corner[0][2] = true;
        if (n->next[0][1] &&
            (n->next[1][2]->next[0][0] != n->next[0][1] ||
            n->next[0][1]->next[2][2] != n->next[1][2]))
            corner[1][2] = corner[0][1] = true;
    }
    if (n->next[0][1]) {
        if (n->next[0][2] && n->next[0][1]->next[1][2] != n->next[0][2])
            corner[0][1] = corner[0][2] = true;
        if (n->next[0][0] && n->next[0][1]->next[1][0] != n->next[0][0])
            corner[0][1] = corner[0][0] = true;
        if (n->next[1][0] &&
            (n->next[0][1]->next[2][0] != n->next[1][0] ||
            n->next[1][0]->next[0][2] != n->next[0][1]))
            corner[0][1] = corner[1][0] = true;
    }
}

void memoize_forced_neighbors(Node* n, int u, int v, bool corner[3][3])
{
    if (u == 1 && v == 1)
        return;
    direction_set& forced_neighbors = n->forced_neighbors[u][v];
    if (u != 1 && v != 1) {
        // diagonal
        if (n->next[2-u][v] && !n->next[2-u][abs(v-1)])
            forced_neighbors.insert(direction(2-u, v));
        if (n->next[u][2-v] && !n->next[abs(u-1)][2-v])
            forced_neighbors.insert(direction(u, 2-v));
        // forced turns
        if (corner[2-u][abs(v-1)]) {
            forced_neighbors.insert(direction(2-u, abs(v-1)));
            if (n->next[2-u][v])
                forced_neighbors.insert(direction(2-u, v));
        }
        if (corner[abs(u-1)][2-v]) {
            forced_neighbors.insert(direction(abs(u-1), 2-v));
            if (n->next[u][2-v])
                forced_neighbors.insert(direction(u, 2-v));
        }
    } else if (u == 1) {
        if (n->next[v][v] && !n->next[v][abs(u-2)])
            forced_neighbors.insert(direction(v, v));
        if (n->next[2-v][v] && !n->next[abs(v-2)][u])
            forced_neighbors.insert(direction(2-v, v));
        // forced turns
        if (corner[v][abs(u-2)]) {
            forced_neighbors.insert(direction(v, abs(u-2)));
            if (n->next[v][v])
                forced_neighbors.insert(direction(v, v));
        }
        if (corner[abs(v-2)][u]) {
            forced_neighbors.insert(direction(abs(v-2), u));
            if (n->next[2-v][v])
                forced_neighbors.insert(direction(2-v, v));
        }
        if (corner[v][2-v]) {
            forced_neighbors.insert(direction(v, 2-v));
            if (n->next[v][u])
                forced_neighbors.insert(direction(v, u));
            if (n->next[v][v])
                forced_neighbors.insert(direction(v, v));
        }
        if (corner[2-v][2-v]) {
            forced_neighbors.insert(direction(2-v, 2-v));
            if (n->next[2-v][u])
                forced_neighbors.insert(direction(2-v, u));
            if (n->next[2-v][v])
                forced_neighbors.insert(direction(2-v, u));
        }
    } else if (v == 1) {
        if (n->next[u][2-u] && !n->next[v][abs(u-2)])
            forced_neighbors.insert(direction(u, 2-u));
        if (n->next[u][u] && !n->next[abs(v-2)][u])
            forced_neighbors.insert(direction(u, u));
        // forced turns
        if (corner[v][abs(u-2)]) {
            forced_neighbors.insert(direction(v, abs(u-2)));
            if (n->next[u][2-u])
                forced_neighbors.insert(direction(u, 2-u));
        }
        if (corner[abs(v-2)][u]) {
            forced_neighbors.insert(direction(abs(v-2), u));
            if (n->next[u][u])
                forced_neighbors.insert(direction(u, u));
        }
        if (corner[2-u][2-u]) {
            forced_neighbors.insert(direction(2-u, 2-u));
            if (n->next[v][2-u])
                forced_neighbors.insert(direction(v, 2-u));
            if (n->next[u][2-u])
                forced_neighbors.insert(direction(u, 2-u));
        }
        if (corner[2-u][u]) {
            forced_neighbors.insert(direction(2-u, u));
            if (n->next[v][u])
                forced_neighbors.insert(direction(v, u));
            if (n->next[u][u])
                forced_neighbors.insert(direction(u, u));
        }
    }
}

NavGraph* generate_navgraph(MapData const* map)
{
    NavGraph* graph = new NavGraph();
    node_map& nodes = graph->nodes;
    for (int y = 0; y < MAP_Y; ++y) {
        for (int x = 0; x < MAP_X; ++x) {
            Node* last = NULL;
            for (int z = 63; z >= 0;) {
                int height = get_potential_node_height(map, x, y, z);
                if (z < 62 && height >= PLAYER_HEIGHT) {
                    Node* n = new Node(x, y, z, height);
                    try_link_nodes(map, nodes, n, 0, 0);
                    try_link_nodes(map, nodes, n, 1, 0);
                    try_link_nodes(map, nodes, n, 2, 0);
                    try_link_nodes(map, nodes, n, 0, 1);
                    
                    if (last == NULL)
                        nodes[get_pos_2d(x, y)] = n;
                    else
                        last->next[1][1] = n;
                    last = n;
                    ++graph->total_nodes;
                }
                z -= height ? height : 1;
            }
        }
    }
    
    // precalculate neighbors
    bool corner[3][3];
    for (node_map::iterator iter = nodes.begin(); iter != nodes.end(); ++iter) {
        memset(corner, false, sizeof(bool) * 3 * 3);
        Node* n = (*iter).second;
        get_corner_flags(corner, n);
        for (int u = 0; u < 3; ++u)
            for (int v = 0; v < 3; ++v)
                memoize_forced_neighbors(n, u, v, corner);
    }
    
    return graph;
}

void print_navgraph_csv(NavGraph* graph)
{
    std::ofstream out("navgraph.csv");
    node_map& nodes = graph->nodes;
    for (node_map::const_iterator iter = nodes.begin(); iter != nodes.end();
        ++iter) {
        Node* node = iter->second;
        do {
            out << get_pos(node->x, node->y, node->z) << ",";
            out << node->x << "," << node->y << "," << node->z << ",";
            out << node->height << ",";
            for (int v = 0; v < 3; ++v) {
                for (int u = 0; u < 3; ++u) {
                    Node* next = node->next[u][v];
                    if (next == NULL || (u == 1 && v == 1))
                        continue;
                    out << next->x << "," << next->y << "," << next->z << ",";
                }
            }
            out << std::endl;
        } while ((node = node->next[1][1]) != NULL);
    }
    out.close();
}

void add_natural_neighbors(direction_set& dirs, int u, int v)
{
    if (u == 1 && v == 1) {
        // only happens at the start of the search
        dirs.insert(direction(0, 0));
        dirs.insert(direction(1, 0));
        dirs.insert(direction(2, 0));
        dirs.insert(direction(0, 1));
        dirs.insert(direction(2, 1));
        dirs.insert(direction(0, 2));
        dirs.insert(direction(1, 2));
        dirs.insert(direction(2, 2));
        return;
    }
    dirs.insert(direction(u, v));
    if (u != 1 && v != 1) {
        // diagonal
        dirs.insert(direction(abs(u-1), v));
        dirs.insert(direction(u, abs(v-1)));
    }
}

inline void add_forced_neighbors(direction_set& dirs, Node const* n, int u, int v)
{
    direction_set const& forced_neighbors = n->forced_neighbors[u][v];
    dirs.insert(forced_neighbors.begin(), forced_neighbors.end());
}

inline bool has_forced_neighbors(Node const* n, int u, int v)
{
    return !n->forced_neighbors[u][v].empty();
}

Node* jump(Node const* a, Node const* goal, int u, int v)
{
    Node* n = a->next[u][v];
    if (n == NULL || n == goal || has_forced_neighbors(n, u, v))
        return n;
    if (u != 1 && v != 1) {
        // diagonal
        if (jump(n, goal, abs(u-1), v) != NULL)
            return n;
        if (jump(n, goal, u, abs(v-1)) != NULL)
            return n;
    }
    return jump(n, goal, u, v);
}

float heuristic_cost_estimate(Node const* a, Node const* goal)
{
    // chebyshev
    //~ return fmax(abs(a->x - goal->x), abs(a->y - goal->y)) * HEURISTIC_COST_SCALE;
    float const x = abs(a->x - goal->x);
    float const y = abs(a->y - goal->y);
    float const z = abs(a->z - goal->z);
    return fmax(x, fmax(y, z)) * HEURISTIC_COST_SCALE;
}

float node_distance(Node const* a, Node const* b)
{
    // euclidean
    //~ if (a->x != b->x && a->y != b->y) {
    if (a->x != b->x && a->y != b->y && a->z != b->z) {
        float const x = a->x - b->x;
        float const y = a->y - b->y;
        float const z = a->z - b->z;
        //~ float const z = 0.0f;
        return sqrt(x * x + y * y + z * z);
    } else {
        return abs(a->x - b->x) + abs(a->y - b->y) + abs(a->z - b->z);
    }
}

bool astar_compute(Node* start, Node* goal)
{
    if (start == NULL || goal == NULL)
        return false;
    node_heap open;
    std::map<Node*, NodeStatus> status;
    NodeStatus n_status;
    direction_set dirs;
    direction_set::const_iterator dir;
    start->g = 0.0f;
    start->h = start->f = heuristic_cost_estimate(start, goal);
    start->prev = NULL;
    open.insert(start);
    int u, v;
    while (!open.empty()) {
        Node* best = open.unlink_min();
        if (best == goal)
            return true;
        status[best] = CLOSED;
        if (best->prev == NULL) {
            u = v = 1;
        } else {
            u = sgn(best->x - best->prev->x) + 1;
            v = sgn(best->y - best->prev->y) + 1;
            assert(u != 1 || v != 1);
        }
        dirs.clear();
        add_forced_neighbors(dirs, best, u, v);
        add_natural_neighbors(dirs, u, v);
        for (dir = dirs.begin(); dir != dirs.end(); ++dir) {
            u = dir->first;
            v = dir->second;
            Node* n = jump(best, goal, u, v);
            if (n == NULL || (n_status = status[n]) == CLOSED)
                continue;
            const float new_g = best->g + node_distance(best, n);
            if (n_status == UNEXPLORED || new_g < n->g) {
                n->g = new_g;
                n->prev = best;
                if (n_status == UNEXPLORED) {
                    n->h = heuristic_cost_estimate(n, goal);
                    n->f = n->g + n->h;
                    open.insert(n);
                    status[n] = OPEN;
                } else {
                    n->f = n->g + n->h;
                    open.decreased_key(n);
                }
            }
        }
    }
    return false;
}

// based on funnel algorithm by Mikko Mononen
int string_pull(float const* portals, int portal_count, float* points,
    int max_points)
{
    int point_count = 0;
    float portal_apex[2], portal_left[2], portal_right[2];
    int apex_i = 0, left_i = 0, right_i = 0;
    v_copy(portal_apex, &portals[0]);
    v_copy(portal_left, &portals[0]);
    v_copy(portal_right, &portals[2]);
    
    v_copy(&points[point_count*2], portal_apex);
    ++point_count;
    
    for (int i = 1; i < portal_count && point_count < max_points; ++i) {
        float const* left = &portals[i*4 + 0];
        float const* right = &portals[i*4 + 2];
        // right
        if (tri_area_2(portal_apex, portal_right, right) >= 0.0f) {
            if (v_equal(portal_apex, portal_right) ||
                tri_area_2(portal_apex, portal_left, right) < 0.0f) {
                v_copy(portal_right, right);
                right_i = i;
            } else {
                // right over left
                v_copy(portal_apex, portal_left);
                apex_i = left_i;
                v_copy(&points[point_count*2], portal_apex);
                ++point_count;
                // restart
                v_copy(portal_right, portal_apex);
                i = right_i = apex_i;
                continue;
            }
        }
        // left
        if (tri_area_2(portal_apex, portal_left, left) <= 0.0f) {
            if (v_equal(portal_apex, portal_left) ||
                tri_area_2(portal_apex, portal_right, left) > 0.0f) {
                v_copy(portal_left, left);
                left_i = i;
            } else {
                // left over right
                v_copy(portal_apex, portal_right);
                apex_i = right_i;
                v_copy(&points[point_count*2], portal_apex);
                ++point_count;
                // restart
                v_copy(portal_left, portal_apex);
                i = left_i = apex_i;
                continue;
            }
        }
    }
    return point_count;
}

int grid_bfs(MapData const* map, float** points, float x1, float y1, float z1,
    float x2, float y2, float z2)
{
    int const min_x = max((int)x1 - HALF_GRID_SIZE, 0);
    int const min_y = max((int)y1 - HALF_GRID_SIZE, 0);
    int const max_x = min((int)x1 + HALF_GRID_SIZE + 1, MAP_X);
    int const max_y = min((int)y1 + HALF_GRID_SIZE + 1, MAP_Y);
    LocalNode* start = NULL;
    LocalNode* goal = NULL;
    
    lnode_vec runs;
    runs.reserve(HALF_GRID_SIZE * 2);
    int x_r = min_x;
    int z = (int)z1;
    for (int y = min_y; y < max_y;) {
        int run = 0;
        for (; x_r < max_x; ++x_r) {
            if (is_walkable(map, x_r, y, z + 1)) {
                ++z;
                ++run;
            } else if (is_walkable(map, x_r, y, z)) {
                ++run;
            } else if (is_walkable(map, x_r, y, z - 1)) {
                --z;
                ++run;
            } else if (run > 0) {
                break;
            }
        }
        if (run > 0) {
            int const x_l = x_r - run;
            LocalNode* new_node = new LocalNode(x_l, x_r, y, z);
            if (start == NULL && (int)y1 == y && x1 >= x_l && x1 <= x_r) {
                start = new_node;
                if (start == goal)
                    break;
            }
            if (goal == NULL && (int)y2 == y && x2 >= x_l && x2 <= x_r) {
                goal = new_node;
                if (start == goal)
                    break;
            }
            for (lnode_vec::iterator iter = runs.begin(); 
                iter != runs.end(); ++iter) {
                LocalNode* i = (*iter);
                if (i->y < y - 1)
                    continue;
                if (i->y >= y)
                    break;
                if ((i->x_l >= x_l && i->x_l < x_r) ||
                    (i->x_r > x_l && i->x_r <= x_r) ||
                    (i->x_l < x_l && i->x_r > x_r)) {
                    // connect overlapping runs
                    new_node->next.push_back(i);
                    i->next.push_back(new_node);
                }
            }
            runs.push_back(new_node);
        }
        if (x_r >= max_x) {
            x_r = min_x;
            z = (int)z1;
            ++y;
        }
    }
    
    if (start == NULL || goal == NULL)
        // start or goal destinations are unreachable
        return 0;
    
    if (start == goal) {
        // start and goal are in the same row, path is a straight line
        *points = new float[2];
        (*points)[0] = x2 + 0.5f;
        (*points)[1] = y2 + 0.5f;
        return 1;
    }
    
    LocalNodeCompare distance_compare(x1, y1, x2, y2);
    std::deque<LocalNode*> lnodes;
    start->visited = true;
    lnodes.push_back(start);
    int visited_nodes = 1;
    while (!lnodes.empty()) {
        LocalNode* best = lnodes.back();
        if (best == goal)
            break;
        lnodes.pop_back();
        lnode_vec& next = best->next;
        // sort potential nodes using a naive distance heuristic
        std::sort(next.begin(), next.end(), distance_compare);
        for (lnode_vec::const_iterator iter = next.begin();
            iter != next.end(); ++iter) {
            if ((*iter)->visited)
                continue;
            (*iter)->visited = true;
            (*iter)->prev = best;
            lnodes.push_front(*iter);
            ++visited_nodes;
        }
    }
    
    if (lnodes.empty())
        // couldn't find a path
        return 0;
    
    int const max_portals = visited_nodes + 2;
    float portals[max_portals*4];
    int portal_count = 0;
    
    // append goal portal
    portals[portal_count*4 + 0] = portals[portal_count*4 + 2] = x2 + 0.5f;
    portals[portal_count*4 + 1] = portals[portal_count*4 + 3] = y2 + 0.5f;
    ++portal_count;
    
    LocalNode* last = goal;
    int last_diff = 0;
    while (goal->prev != NULL) {
        LocalNode* prev = goal->prev;
        int diff = goal->y - prev->y;
        float left[2];
        float right[2];
        left[1] = right[1] = goal->y + 0.5f;
        if (last_diff == 0 || last_diff == diff) {
            left[0] = max(goal->x_l, prev->x_l) + 0.5f;
            right[0] = min(goal->x_r, prev->x_r) - 0.5f;
        } else {
            // turned around a corner
            left[0] = max(last->x_l, prev->x_l) + 0.5f;
            right[0] = min(last->x_r, prev->x_r) - 0.5f;
        }
        // note: left and right are swapped if diff < 0
        v_copy(&portals[portal_count*4 + abs(diff - 1)], left);
        v_copy(&portals[portal_count*4 + diff + 1], right);
        
        ++portal_count;
        last_diff = diff;
        last = goal;
        goal = prev;
    }
    
    // append start portal
    portals[portal_count*4 + 0] = portals[portal_count*4 + 2] = x1;
    portals[portal_count*4 + 1] = portals[portal_count*4 + 3] = y1;
    ++portal_count;
    
    assert(portal_count <= max_portals);
    
    *points = new float[portal_count*2];
    int point_count = string_pull(portals, portal_count, *points, portal_count);
    
    // shrink superfluous starting point
    float* last_point = &(*points)[(point_count - 1)*2];
    if (last_point[0] == x1 && last_point[1] == y1)
        --point_count;
    
    return point_count;
}