-- A new method of grouping orders is being evalulated for the difference in cost it will create
-- In this method, lines shipped to the same place on the same date are grouped together
-- regardless of their order number
-- This contrasts the existing method which does not group together lines going to the same 
-- place at the same date if they have differing order numbers

-- The first section creates the new total quantity of items needing to be picked for each line 
-- and calculates the number of picks in each of these enw lines

-- The new grouping with new order lines is greated
WITH CTE_proposed_grouping AS (
    SELECT date_and_ship_to_address, article_id, each_per_pallet, each_per_case, product_type,
        SUM(quantity_eaches_requested_for_order) OVER
            (PARTITION BY date_and_ship_to_address, article_id) AS article_qty_ea_request_for_order
    FROM existing_pick_costs 
),
-- The number of pallet picks for each order in this new grouping is calculated
-- The maximum number of full pallet picks possible are picked for each group as pallet picks move 
-- the greatest number of items for the least amount of labor
CTE_proposed_plt_picks AS (
    SELECT FLOOR(article_qty_ea_request_for_order / each_per_pallet) AS proposed_plt_picks,
        date_and_ship_to_address, article_id  
    FROM CTE_proposed_grouping
),
-- The number of eaches remaining after the pallet picks are performed in the new grouping is calculated
CTE_remaining_ea_from_plt_pick AS (
    SELECT (article_qty_ea_request_for_order - each_per_pallet * proposed_plt_picks) AS remaining_ea_from_plt_pick,
        pg.date_and_ship_to_address, pg.article_id  
    FROM CTE_proposed_grouping AS pg
    INNER JOIN CTE_proposed_plt_picks AS plt ON 
        pg.date_and_ship_to_address = plt.date_and_ship_to_address
        AND pg.article_id  = plt.article_id 
),
-- The number of case picks in the new grouping is calculated
-- After pallet picks, case picks move the greatest amount of product for the least amount of labor
-- For this reason, we take the greatest number of full case picks that can be made from the quantity 
-- remaining after pallets picks
CTE_proposed_cs_picks AS (
    SELECT 
    CASE WHEN pg.each_per_case = 0 THEN 0
    ELSE FLOOR(ea_from_plt.remaining_ea_from_plt_pick / pg.each_per_case) 
    END AS proposed_cs_picks,
    pg.date_and_ship_to_address, pg.article_id  
    FROM CTE_proposed_grouping AS pg
        INNER JOIN CTE_remaining_ea_from_plt_pick AS ea_from_plt ON 
        pg.date_and_ship_to_address = ea_from_plt.date_and_ship_to_address
        AND pg.article_id  = ea_from_plt.article_id 
),
-- The number of eaches remaining after both case and pallet picks are performed in the 
-- new grouping is calculated
CTE_remaining_ea_from_cs_pick AS(
    SELECT (ea_from_plt.remaining_ea_from_plt_pick - pg.each_per_case * 
        cs.proposed_cs_picks) AS remaining_ea_from_cs_pick,
    pg.date_and_ship_to_address, pg.article_id  
    FROM CTE_proposed_grouping AS pg
    INNER JOIN CTE_proposed_cs_picks AS cs ON 
    pg.date_and_ship_to_address = cs.date_and_ship_to_address
    AND pg.article_id  = cs.article_id 
    INNER JOIN CTE_remaining_ea_from_plt_pick AS ea_from_plt ON 
    ea_from_plt.date_and_ship_to_address = cs.date_and_ship_to_address
    AND ea_from_plt.article_id  = cs.article_id 
),

-- Next section calculates new costs from updated pick information

-- The costs incurred from the pallet picks are calculated
CTE_proposed_pallet_pick_costs AS(
    SELECT pg.date_and_ship_to_address, pg.article_id,
    plt.proposed_plt_picks * cbp.cost_per_pick AS prop_cost_of_plt_picks
    FROM CTE_proposed_grouping AS pg
    INNER JOIN cost_by_pick AS cbp
    ON pg.product_type = cbp.product_type AND cbp.pick_uom = 'Pallet'
    INNER JOIN CTE_proposed_plt_picks AS plt ON 
    plt.date_and_ship_to_address = pg.date_and_ship_to_address
    AND plt.article_id  = pg.article_id 
),
-- The costs incurred from the case picks are calculated
CTE_proposed_case_pick_costs AS(
    SELECT pg.date_and_ship_to_address, pg.article_id,
    cs.proposed_cs_picks * cbp.cost_per_pick AS prop_cost_of_cs_picks
    FROM CTE_proposed_grouping AS pg
    INNER JOIN cost_by_pick AS cbp
    ON pg.product_type = cbp.product_type AND cbp.pick_uom = 'Case'
    INNER JOIN CTE_proposed_cs_picks AS cs  ON 
    cs.date_and_ship_to_address = pg.date_and_ship_to_address
    AND cs.article_id  = pg.article_id 
),
-- The costs incurred from the case picks are calculated
-- Remaining eaches after cases and pallets are picked must be picked as each picks as previous
-- calulations have taken the maximum number of full pallet and case picks possible
CTE_proposed_each_pick_costs AS(
    SELECT pg.date_and_ship_to_address, pg.article_id,
    ea.remaining_ea_from_cs_pick * cbp.cost_per_pick AS prop_cost_of_ea_picks
    FROM CTE_proposed_grouping AS pg
    INNER JOIN cost_by_pick AS cbp
    ON pg.product_type = cbp.product_type AND cbp.pick_uom = 'Each'
    INNER JOIN CTE_remaining_ea_from_cs_pick AS ea  ON 
    ea.date_and_ship_to_address = pg.date_and_ship_to_address
    AND ea.article_id  = pg.article_id 
)

-- Calculate the total pick costs from the new grouping
SELECT 
  SUM(pallet.prop_cost_of_plt_picks + case_pick.prop_cost_of_cs_picks + each_pick.prop_cost_of_ea_picks)
FROM CTE_proposed_pallet_pick_costs AS pallet
INNER JOIN CTE_proposed_case_pick_costs AS case_pick
  ON pallet.date_and_ship_to_address = case_pick.date_and_ship_to_address
  AND pallet.article_id = case_pick.article_id
INNER JOIN CTE_proposed_each_pick_costs AS each_pick
  ON pallet.date_and_ship_to_address = each_pick.date_and_ship_to_address
  AND pallet.article_id = each_pick.article_id;

-- We can compare this to the costs using the existing method of grouping
SELECT SUM(line_pick_cost) FROM existing_pick_costs;