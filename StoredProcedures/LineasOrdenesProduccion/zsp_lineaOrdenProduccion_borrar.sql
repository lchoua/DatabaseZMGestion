DROP PROCEDURE IF EXISTS `zsp_lineaOrdenProduccion_borrar`;

DELIMITER $$
CREATE PROCEDURE `zsp_lineaOrdenProduccion_borrar`(pIn JSON)
SALIR:BEGIN
    /*
        Procedimiento que permite borrar una linea de orden de produccion. 
        Controla que la linea de orden de produccion este en estado 'PendienteDeProduccion'.
        Devuelve el NULL en 'respuesta' o el error en 'error'.
    */

    -- Control de permisos
    DECLARE pUsuariosEjecuta JSON;
    DECLARE pIdUsuarioEjecuta SMALLINT;
    DECLARE pToken VARCHAR(256);
    DECLARE pMensaje TEXT;

    -- Linea de presupuesto
    DECLARE pIdLineaProducto BIGINT;

    DECLARE pIdRemito INT;

    -- Para la respuesta
    DECLARE pRespuesta JSON;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        SHOW ERRORS;
        SELECT f_generarRespuesta("ERROR_TRANSACCION", NULL) pOut;
        ROLLBACK;
	END;

    SET pUsuariosEjecuta = pIn ->> "$.UsuariosEjecuta";
    SET pToken = pUsuariosEjecuta ->> "$.Token";

    CALL zsp_usuario_tiene_permiso(pToken, 'zsp_lineaOrdenProduccion_borrar', pIdUsuarioEjecuta, pMensaje);
    IF pMensaje != 'OK' THEN
        SELECT f_generarRespuesta(pMensaje, NULL) pOut;
        LEAVE SALIR;
    END IF;

    -- Extraigo atributos de la linea de presupuesto
    SET pIdLineaProducto = COALESCE(pIn ->> "$.LineasProducto.IdLineaProducto", 0);

    IF NOT EXISTS (SELECT IdLineaProducto FROM LineasProducto WHERE IdLineaProducto = pIdLineaProducto AND Tipo = 'O') THEN
        SELECT f_generarRespuesta("ERROR_NOEXISTE_LINEA_ORDEN_PRODUCCION", NULL) pOut;
        LEAVE SALIR;
    END IF;

    IF (SELECT Estado FROM LineasProducto WHERE IdLineaProducto = pIdLineaProducto) NOT IN('F','C') 
        OR EXISTS(SELECT IdTarea FROM Tareas WHERE IdLineaProducto = pIdLineaProducto AND Estado NOT IN('P','C'))
    THEN
        SELECT f_generarRespuesta("ERROR_BORRAR_LINEA_ORDEN_PRODUCCION", NULL) pOut;
        LEAVE SALIR;
    END IF;

    -- Obtenemos el IdRemito de "Transformación entrada" (X) asociado, en caso de que se esté fabricando utilizando esqueletos
    SELECT DISTINCT r.IdRemito INTO pIdRemito 
        FROM LineasProducto lop 
        INNER JOIN LineasProducto lr ON lr.IdLineaProductoPadre = lop.IdLineaProducto 
        INNER JOIN Remitos r ON lr.IdReferencia = r.IdRemito AND lr.Tipo = 'R' 
        WHERE 
            r.Tipo = 'X' 
            AND lop.IdLineaProducto = pIdLineaProducto 
            AND lop.Tipo = 'O';

    START TRANSACTION;
        IF COALESCE(pIdRemito, 0) != 0 THEN
            -- Eliminamos todas las lineas de remito del remito
            DELETE FROM LineasProducto
            WHERE 
                IdReferencia = pIdRemito
                AND IdLineaProductoPadre = pIdLineaProducto
                AND Tipo = 'R';

            -- Eliminamos el remito
            DELETE FROM Remitos
            WHERE IdRemito = pIdRemito;
        END IF;

        DELETE
        FROM LineasProducto 
        WHERE IdLineaProducto = pIdLineaProducto;
        
		SELECT f_generarRespuesta(NULL, NULL) AS pOut;
    COMMIT;
END $$
DELIMITER ;
